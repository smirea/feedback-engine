import { afterAll, expect, test } from 'bun:test';
import { spawn, type ChildProcess } from 'node:child_process';
import { cpSync, mkdtempSync, readdirSync, renameSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium, type Browser, type Page } from 'playwright';
import env from '../../../env.ts';
import { root } from './app.ts';

/**
 * Apps outside this repository, as ones that install the package from npm: plain Vite, run by Node. The example
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
		env: { ...process.env, NODE_ENV: undefined, NEXT_TELEMETRY_DISABLED: '1' },
		stdout: 'pipe',
		stderr: 'pipe',
	});
	if (result.exitCode !== 0) throw new Error(`${command.join(' ')} failed:\n${result.stdout}${result.stderr}`);
}

const vite = {
	build: ['node', 'node_modules/vite/bin/vite.js', 'build'],
	dev: (port: number) => [
		'node',
		'node_modules/vite/bin/vite.js',
		'--host',
		'127.0.0.1',
		'--port',
		String(port),
		'--strictPort',
	],
	preview: (port: number) => [
		'node',
		'node_modules/vite/bin/vite.js',
		'preview',
		'--host',
		'127.0.0.1',
		'--port',
		String(port),
		'--strictPort',
	],
};

/** Copies a fixture out of the repository, installs the packed package into it, type-checks it if asked, and builds it. */
function install(fixture: string, { check, build }: { check?: string[]; build: string[] }) {
	const app = mkdtempSync(join(tmpdir(), `feedback-${fixture}-`));
	cpSync(join(import.meta.dir, fixture), app, { recursive: true });
	// The release publishes with npm, so the apps install what npm packs.
	run(['npm', 'pack', '--pack-destination', app], join(root, 'packages/web'));
	renameSync(
		join(
			app,
			readdirSync(app).find(name => name.endsWith('.tgz'))!,
		),
		join(app, 'feedback-engine.tgz'),
	);
	run(['bun', 'install'], app);
	if (check) run(check, app);
	run(build, app);
	return app;
}

/** Starts one of the app's servers and opens it once the page has the engine. */
async function serve(app: string, command: string[]) {
	const state = { log: '', errors: [] as string[] };
	const port = Number(command.at(-1) === '--strictPort' ? command.at(-2) : command.at(-1));
	const server = spawn(command[0]!, command.slice(1), {
		cwd: app,
		env: { ...process.env, NODE_ENV: undefined, NEXT_TELEMETRY_DISABLED: '1' },
		stdio: 'pipe',
	});
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
		if (attempt === 150) throw new Error(`The server did not start:\n${state.log}`);
		await Bun.sleep(100);
	}

	browser ??= await chromium.launch();
	const page = await browser.newPage();
	page.on('pageerror', error => state.errors.push(String(error)));
	page.on('console', message => {
		if (message.type() === 'error') state.errors.push(message.text());
	});
	await page.goto(url);
	await page.waitForFunction(() => globalThis.__feedbackEngine);
	return { page, state };
}

/** Opens the editor through the automation entry, then reads the page's tree the way the editor does. */
async function captured(page: Page) {
	await page.evaluate(() => globalThis.__feedbackEngine!.present());
	const report = JSON.parse(
		await page.evaluate(() => (globalThis as unknown as { captureReport: () => Promise<string> }).captureReport()),
	);
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

test('a Svelte app that installs the packed package builds, serves through the optimizer, and reads its tagged components', async () => {
	const app = install('consumer', vite);
	// The dev server pre-bundles the package. The log would carry the optimizer's error, which the page only shows as a failed import.
	const dev = await serve(app, vite.dev(env.UI_PORT + 4));
	await dev.page.evaluate(() => globalThis.__feedbackEngine!.present());
	expect(dev.state.log).not.toContain('Error');
	expect(dev.state.errors).toEqual([]);

	// The capture hook reaches the package's modules past the optimizer, so the tree is read from the build.
	const { page, state } = await serve(app, vite.preview(env.UI_PORT + 3));
	const report = await captured(page);
	expect(report.tree).toEqual([
		['Screen', undefined, undefined],
		['  App', 'src/App.svelte:7', 'count: 3'],
		['    Header "Consumer"', undefined, undefined],
		['    Button "Count 3"', undefined, undefined],
	]);
	expect(report.app).toBe('Consumer');
	expect(state.errors).toEqual([]);
}, 180_000);

test('a React 18 app that installs the packed package type-checks, builds, serves, and reads memo, forwardRef, fragment, class, and portal components', async () => {
	// The app's compiler options are stricter than the package's, so this fails if the app compiles the package's source.
	const app = install('consumer-react', { ...vite, check: ['node', 'node_modules/typescript/bin/tsc', '--noEmit'] });
	const { page, state } = await serve(app, vite.dev(env.UI_PORT + 8));
	const report = await captured(page);
	expect(report.tree).toEqual([
		['Screen', undefined, undefined],
		// `App` is tagged under its own name, so its data is the tag's. `Theme` draws nothing of its own and shares its box.
		['  App', 'src/App.tsx:44', 'count: 3'],
		['    Theme', 'src/App.tsx:40', undefined],
		['      Header "Consumer"', 'src/App.tsx:49', undefined],
		// `memo`, with JSX as a prop.
		['      Card', 'src/App.tsx:5', 'title: Counter\nicon: <Icon>'],
		['        Button "Count 3"', 'src/App.tsx:51', undefined],
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

test('a Next.js app that installs the packed package builds with Turbopack, serves, and reads client and server components', async () => {
	const next = 'node_modules/next/dist/bin/next';
	const app = install('consumer-next', { build: ['node', next, 'build'] });
	const { page, state } = await serve(app, [
		'node',
		next,
		'start',
		'--hostname',
		'127.0.0.1',
		'--port',
		String(env.UI_PORT + 9),
	]);
	const report = await captured(page);
	expect(report.tree).toEqual([
		['Screen', undefined, undefined],
		['  App', 'app/App.tsx:49', 'count: 3'],
		['    Theme', 'app/App.tsx:45', undefined],
		['      Header "Consumer"', 'app/App.tsx:54', undefined],
		['      Card', 'app/App.tsx:7', 'title: Counter\nicon: <Icon>'],
		['        Button "Count 3"', 'app/App.tsx:56', undefined],
		['      Field', 'app/App.tsx:16', 'label: Name'],
		['        Text field "Name"', 'app/App.tsx:17', undefined],
		['      Pair', 'app/App.tsx:20', 'first: One\nsecond: Two'],
		['        Text "One"', 'app/App.tsx:22', undefined],
		['        Text "Two"', 'app/App.tsx:23', undefined],
		['      Legend', 'app/App.tsx:27', 'note: Legend'],
		['        Text "Legend"', 'app/App.tsx:29', undefined],
		['      Footer', 'app/App.tsx:61', undefined],
		['        Text "Footer"', 'app/App.tsx:61', undefined],
		// Drawn by a server component, which leaves no component in the page. A production build keeps the element's line, because the app asks for it.
		['  Text "Served"', 'app/page.tsx:8', undefined],
		['  Toast', 'app/App.tsx:37', 'message: Saved'],
		['    Text "Saved"', 'app/App.tsx:41', undefined],
	]);
	expect(report.app).toBe('Consumer');
	expect(state.log).not.toContain('Error');
	expect(state.errors).toEqual([]);
}, 240_000);
