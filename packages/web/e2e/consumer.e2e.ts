import { afterAll, expect, test } from 'bun:test';
import { spawn, type ChildProcess } from 'node:child_process';
import { cpSync, mkdtempSync, readdirSync, renameSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium, type Browser } from 'playwright';
import env from '../../../examples/todo-svelte/env.ts';
import { root } from './app.ts';

/**
 * An app outside this repository, as one that installs the package from GitHub: plain Svelte and Vite, run by Node.
 * The example app links the package from the workspace, which skips what Vite does to a package in `node_modules`.
 */
const port = env.UI_PORT + 4;
let server: ChildProcess | undefined;
let browser: Browser | undefined;

afterAll(async () => {
	await browser?.close();
	server?.kill();
});

function run(command: string[], cwd: string) {
	const result = Bun.spawnSync(command, {
		cwd,
		env: { ...process.env, NODE_ENV: undefined },
		stdout: 'pipe',
		stderr: 'pipe',
	});
	if (result.exitCode !== 0) throw new Error(`${command.join(' ')} failed:\n${result.stdout}${result.stderr}`);
}

test('an app that installs the packed package builds, serves, and exports feedback', async () => {
	const app = mkdtempSync(join(tmpdir(), 'feedback-consumer-'));
	cpSync(join(import.meta.dir, 'consumer'), app, { recursive: true });
	run(['bun', 'pm', 'pack', '--destination', app], root);
	renameSync(
		join(
			app,
			readdirSync(app).find(name => name.endsWith('.tgz'))!,
		),
		join(app, 'feedback-engine.tgz'),
	);
	run(['bun', 'install'], app);
	run(['node', 'node_modules/vite/bin/vite.js', 'build'], app);

	let log = '';
	server = spawn(
		'node',
		['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', String(port), '--strictPort'],
		{
			cwd: app,
			env: { ...process.env, NODE_ENV: undefined },
			stdio: 'pipe',
		},
	);
	server.stdout!.on('data', chunk => (log += chunk));
	server.stderr!.on('data', chunk => (log += chunk));
	const url = `http://127.0.0.1:${port}/`;
	for (let attempt = 0; ; attempt++) {
		if (
			await fetch(url).then(
				response => response.ok,
				() => false,
			)
		)
			break;
		if (attempt === 150) throw new Error(`The dev server did not start:\n${log}`);
		await Bun.sleep(100);
	}

	browser = await chromium.launch();
	const page = await browser.newPage();
	const errors: string[] = [];
	page.on('pageerror', error => errors.push(String(error)));
	page.on('console', message => {
		if (message.type() === 'error') errors.push(message.text());
	});
	await page.goto(url);
	await page.getByRole('button', { name: 'Count 3' }).click();
	await page.keyboard.press('Alt+Shift+F');
	await page.getByRole('button', { name: 'Add Feedback' }).click();
	const field = page.getByRole('textbox', { name: 'Feedback text' });
	await field.fill('Bigger button');
	await field.press('Enter');
	await page.getByRole('button', { name: 'Share' }).click();
	await page.getByRole('menuitem', { name: 'JSON', exact: true }).click();
	await page.getByRole('dialog', { name: 'Share JSON' }).waitFor();
	const report = JSON.parse(await page.evaluate(() => globalThis.__feedbackEngine!.lastExport[0]!.blob.text()));

	expect(
		report.nodes.map((node: { kind: string; name: string; label?: string; source?: string; data?: string }) => [
			node.kind,
			node.name,
			node.label,
			node.source,
			node.data,
		]),
	).toEqual([
		['screen', 'Screen', undefined, undefined, undefined],
		['component', 'App', undefined, 'src/App.svelte:7', 'count: 4'],
		['element', 'Header', 'Consumer', 'src/App.svelte:8', undefined],
		['element', 'Button', 'Count 4', 'src/App.svelte:9', undefined],
	]);
	expect(report.app).toBe('Consumer');
	// The log would carry the optimizer's error, which the page only shows as a failed import.
	expect(log).not.toContain('Error');
	expect(errors).toEqual([]);
}, 180_000);
