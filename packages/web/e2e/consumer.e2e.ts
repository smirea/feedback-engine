import { afterAll, expect, test } from 'bun:test';
import { spawn, type ChildProcess } from 'node:child_process';
import { cpSync, mkdtempSync, readdirSync, renameSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium, type Browser, type Page } from 'playwright';
import env from '../../../env.ts';
import { root } from './app.ts';

/**
 * Apps outside this repository, as ones that install the package from GitHub: plain Vite, run by Node. The example
 * apps link the package from the workspace, which skips what Vite does to a package in `node_modules`.
 */
const servers: ChildProcess[] = [];
let browser: Browser | undefined;

afterAll(async () => {
	await browser?.close();
	for (const server of servers) server.kill();
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

/** Copies a fixture out of the repository, installs the packed package into it, builds it, and opens its dev server. */
async function consume(fixture: string, port: number, check?: string[]) {
	const app = mkdtempSync(join(tmpdir(), `feedback-${fixture}-`));
	cpSync(join(import.meta.dir, fixture), app, { recursive: true });
	run(['bun', 'pm', 'pack', '--destination', app], root);
	renameSync(
		join(
			app,
			readdirSync(app).find(name => name.endsWith('.tgz'))!,
		),
		join(app, 'feedback-engine.tgz'),
	);
	run(['bun', 'install'], app);
	if (check) run(check, app);
	run(['node', 'node_modules/vite/bin/vite.js', 'build'], app);

	const state = { log: '', errors: [] as string[] };
	const server = spawn(
		'node',
		['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', String(port), '--strictPort'],
		{
			cwd: app,
			env: { ...process.env, NODE_ENV: undefined },
			stdio: 'pipe',
		},
	);
	servers.push(server);
	server.stdout!.on('data', chunk => (state.log += chunk));
	server.stderr!.on('data', chunk => (state.log += chunk));
	const url = `http://127.0.0.1:${port}/`;
	for (let attempt = 0; ; attempt++) {
		if (
			await fetch(url).then(
				response => response.ok,
				() => false,
			)
		)
			break;
		if (attempt === 150) throw new Error(`The dev server did not start:\n${state.log}`);
		await Bun.sleep(100);
	}

	browser ??= await chromium.launch();
	const page = await browser.newPage();
	page.on('pageerror', error => state.errors.push(String(error)));
	page.on('console', message => {
		if (message.type() === 'error') state.errors.push(message.text());
	});
	await page.goto(url);
	return { page, state };
}

/** Gives feedback the way a person does, from `open` to the JSON export, and returns the tree. */
async function exported(page: Page, open: () => Promise<void>) {
	await page.getByRole('button', { name: 'Count 3' }).click();
	await open();
	const field = page.getByRole('textbox', { name: 'Feedback text' });
	await field.fill('Bigger button');
	await field.press('Enter');
	await page.getByRole('button', { name: 'Share' }).click();
	await page.getByRole('menuitem', { name: 'JSON', exact: true }).click();
	await page.getByRole('dialog', { name: 'Share JSON' }).waitFor();
	const report = JSON.parse(await page.evaluate(() => globalThis.__feedbackEngine!.lastExport[0]!.blob.text()));
	const depth = new Map<number, number>();
	return {
		app: report.app as string,
		tree: (
			report.nodes as { id: number; parent?: number; name: string; label?: string; source?: string; data?: string }[]
		).map(node => {
			depth.set(node.id, node.parent === undefined ? 0 : depth.get(node.parent)! + 1);
			const title = node.label ? `${node.name} "${node.label}"` : node.name;
			return [`${'  '.repeat(depth.get(node.id)!)}${title}`, node.source, node.data];
		}),
	};
}

test('a Svelte app that installs the packed package builds, serves, and exports feedback', async () => {
	const { page, state } = await consume('consumer', env.UI_PORT + 4);
	// This app sets a keyboard shortcut, which shows the pill.
	const report = await exported(page, async () => {
		await page.keyboard.press('Alt+Shift+F');
		await page.getByRole('button', { name: 'Add Feedback' }).click();
	});
	expect(report.tree).toEqual([
		['Screen', undefined, undefined],
		['  App', 'src/App.svelte:7', 'count: 4'],
		['    Header "Consumer"', 'src/App.svelte:8', undefined],
		['    Button "Count 4"', 'src/App.svelte:9', undefined],
	]);
	expect(report.app).toBe('Consumer');
	// The log would carry the optimizer's error, which the page only shows as a failed import.
	expect(state.log).not.toContain('Error');
	expect(state.errors).toEqual([]);
}, 180_000);

test('a React 18 app that installs the packed package type-checks, builds, serves, and exports feedback', async () => {
	// The app's compiler options are stricter than the package's, so this fails if the app compiles the package's source.
	const { page, state } = await consume('consumer-react', env.UI_PORT + 8, [
		'node',
		'node_modules/typescript/bin/tsc',
		'--noEmit',
	]);
	await page.getByRole('heading', { name: 'Consumer' }).waitFor();
	const report = await exported(page, () =>
		page.getByRole('heading', { name: 'Consumer' }).click({ modifiers: ['Alt', 'Meta'] }),
	);
	expect(report.tree).toEqual([
		['Screen', undefined, undefined],
		// `App` is tagged under its own name, so its data is the tag's. `Theme` draws nothing of its own and shares its box.
		['  App', 'src/App.tsx:44', 'count: 4'],
		['    Theme', 'src/App.tsx:40', undefined],
		['      Header "Consumer"', 'src/App.tsx:49', undefined],
		// `memo`, with JSX as a prop.
		['      Card', 'src/App.tsx:5', 'title: Counter\nicon: <Icon>'],
		['        Button "Count 4"', 'src/App.tsx:51', undefined],
		// `forwardRef`.
		['      Field', 'src/App.tsx:14', 'label: Name'],
		['        Text field "Name"', 'src/App.tsx:15', undefined],
		// A fragment: one box around both paragraphs.
		['      Pair', 'src/App.tsx:18', 'first: One\nsecond: Two'],
		['        Text "One"', 'src/App.tsx:20', undefined],
		['        Text "Two"', 'src/App.tsx:21', undefined],
		// A class.
		['      Legend', 'src/App.tsx:25', 'note: Legend'],
		['        Text "Legend"', 'src/App.tsx:27', undefined],
		// A region tagged inline.
		['      Footer', 'src/App.tsx:56', undefined],
		['        Text "Footer"', 'src/App.tsx:56', undefined],
		// A portal: the component is where it draws.
		['  Toast', 'src/App.tsx:35', 'message: Saved'],
		['    Text "Saved"', 'src/App.tsx:36', undefined],
	]);
	expect(report.app).toBe('Consumer');
	expect(state.log).not.toContain('Error');
	expect(state.errors).toEqual([]);
}, 180_000);
