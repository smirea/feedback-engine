import { spawn, type ChildProcess } from 'node:child_process';
import { join } from 'node:path';
import pixelmatch from 'pixelmatch';
import { chromium, webkit, type Browser, type BrowserContext, type Page } from 'playwright';
import { PNG } from 'pngjs';
import env from '../../../examples/todo-svelte/env.ts';
import type { FeedbackEngine } from '../src/svelte/index.ts';

export const root = join(import.meta.dir, '../../..');
const example = join(root, 'examples/todo-svelte');

export type Mode = 'dev' | 'preview';
export const modes: Mode[] = ['dev', 'preview'];
export const engines = { chromium, webkit };
export type EngineName = keyof typeof engines;

// Beside the port `bun run dev` uses, so the tests run while the example app is open.
const ports = { dev: env.UI_PORT + 1, preview: env.UI_PORT + 2, procrastimate: env.UI_PORT + 3 };
export const url = (mode: Mode, path = '/') => `http://127.0.0.1:${ports[mode]}${path}`;

/** A stand-in for ProcrastiMate's agent API that keeps what it was sent. The dev server's proxy forwards to it. */
export const procrastimate = {
	token: 'test-token',
	uploads: new Map<string, { type: string; bytes: number }>(),
	tasks: [] as {
		id: string;
		title: string;
		projectId: string | null;
		sectionId: string | null;
		attachments?: unknown[];
	}[],
	unauthorized: 0,
};

function serveProcrastimate(port: number) {
	return Bun.serve({
		port,
		hostname: '127.0.0.1',
		async fetch(request) {
			const { pathname, searchParams } = new URL(request.url);
			if (request.headers.get('authorization') !== `Bearer ${procrastimate.token}`) {
				procrastimate.unauthorized += 1;
				return Response.json({ message: 'Not signed in' }, { status: 401 });
			}
			const id = searchParams.get('id');
			if (request.method === 'GET' && pathname === '/api/view') {
				return Response.json({
					projects: [
						{ id: 'p2', name: 'Later', order: 2, createdAt: 1 },
						{ id: 'p1', name: 'Todo app', order: 1, createdAt: 1 },
					],
					sections: [
						{ id: 's2', projectId: 'p1', name: 'Polish', order: 2, createdAt: 1 },
						{ id: 's1', projectId: 'p1', name: 'Bugs', order: 1, createdAt: 1 },
					],
				});
			}
			if (request.method === 'PUT' && pathname === '/api/images') {
				const bytes = (await request.arrayBuffer()).byteLength;
				procrastimate.uploads.set(`${id}/${searchParams.get('size')}`, {
					type: request.headers.get('content-type')!,
					bytes,
				});
				return Response.json({});
			}
			if (request.method === 'POST' && pathname === '/api/tasks') {
				const task = { id: `task-${procrastimate.tasks.length + 1}`, ...((await request.json()) as object) };
				procrastimate.tasks.push(task as (typeof procrastimate.tasks)[number]);
				return Response.json(task);
			}
			if (request.method === 'PATCH' && pathname === '/api/tasks') {
				Object.assign(
					procrastimate.tasks.find(task => task.id === id)!,
					await request.json(),
				);
				return Response.json({});
			}
			return Response.json({ message: 'Not found' }, { status: 404 });
		},
	});
}

const servers: ChildProcess[] = [];
let stand: ReturnType<typeof serveProcrastimate> | undefined;
const browsers = new Map<EngineName, Browser>();

export async function startServers() {
	// `bun test` sets NODE_ENV to `test`, which would make this a development build.
	const build = Bun.spawnSync(['bun', 'run', 'build'], {
		cwd: root,
		env: { ...process.env, NODE_ENV: 'production' },
		stdout: 'pipe',
		stderr: 'pipe',
	});
	if (build.exitCode !== 0) throw new Error(`The example app did not build:\n${build.stderr}`);
	stand = serveProcrastimate(ports.procrastimate);
	for (const mode of modes) {
		const child = spawn(
			'bun',
			[
				'--env-file=../../.env',
				'--env-file=../../.env.local',
				'--bun',
				'vite',
				...(mode === 'preview' ? ['preview'] : []),
				'--host',
				'127.0.0.1',
				'--port',
				String(ports[mode]),
				'--strictPort',
			],
			{
				cwd: example,
				stdio: 'pipe',
				env: {
					...process.env,
					PROCRASTIMATE_URL: `http://127.0.0.1:${ports.procrastimate}`,
					PROCRASTIMATE_TOKEN: procrastimate.token,
				},
			},
		);
		let log = '';
		child.stdout!.on('data', chunk => (log += chunk));
		child.stderr!.on('data', chunk => (log += chunk));
		servers.push(child);
		for (let attempt = 0; ; attempt++) {
			if (
				await fetch(url(mode)).then(
					response => response.ok,
					() => false,
				)
			)
				break;
			if (attempt === 150) throw new Error(`The ${mode} server did not start:\n${log}`);
			await Bun.sleep(100);
		}
	}
}

export async function stopServers() {
	for (const browser of browsers.values()) await browser.close();
	for (const server of servers) server.kill();
	await stand?.stop(true);
}

export type Opened = { page: Page; context: BrowserContext; errors: string[] };

/** Opens a page of the example app. `errors` collects page errors and console errors, which every test expects to stay empty. */
export async function open(
	engine: EngineName,
	mode: Mode,
	path: string,
	viewport = { width: 390, height: 700 },
): Promise<Opened> {
	if (!browsers.has(engine)) browsers.set(engine, await engines[engine].launch());
	const context = await browsers.get(engine)!.newContext({ viewport, deviceScaleFactor: 2 });
	if (engine === 'chromium') await context.grantPermissions(['clipboard-read', 'clipboard-write']);
	const page = await context.newPage();
	const errors: string[] = [];
	page.on('pageerror', error => errors.push(String(error)));
	page.on('console', message => {
		if (message.type() === 'error') errors.push(message.text());
	});
	await page.goto(url(mode, path));
	await page.getByRole('heading', { level: 1 }).waitFor();
	return { page, context, errors };
}

export const editor = (page: Page) => page.getByRole('dialog', { name: 'Feedback', exact: true });
export const canvas = (page: Page) => page.getByRole('img', { name: /^Screenshot/ });
export const field = (page: Page) => page.getByRole('textbox', { name: 'Feedback text' });

/** Opens the editor the way an app's own button does. */
export async function present(page: Page) {
	await page.evaluate(() => globalThis.__feedbackEngine!.present());
	await editor(page).waitFor();
}

/** Clicks the screenshot at a point given in the captured page's own coordinates. */
export async function tap(page: Page, x: number, y: number) {
	const box = (await canvas(page).boundingBox())!;
	const size = await page.evaluate(() => {
		const drawn = document.querySelector('[data-feedback-engine]')!.shadowRoot!.querySelector('canvas')!;
		return { width: drawn.width, height: drawn.height };
	});
	const scale = box.width / (size.width / 2);
	await canvas(page).evaluate((node, to) => node.parentElement!.scrollTo(to), {
		top: Math.max(0, y * scale - 100),
		left: Math.max(0, x * scale - 100),
	});
	const moved = (await canvas(page).boundingBox())!;
	await page.mouse.click(moved.x + x * scale, moved.y + y * scale);
}

export type Report = {
	app: string;
	size: { width: number; height: number };
	visible: { x: number; y: number; width: number; height: number };
	environment: { name: string; value: string }[];
	context: { name: string; value: string }[];
	items: { number: number; text: string; target: number; title: string; path: number[]; code?: string }[];
	references: { number: number; token: string; target: number; title: string }[];
	nodes: {
		id: number;
		parent?: number;
		layer: number;
		kind: string;
		name: string;
		label?: string;
		frame: { x: number; y: number; width: number; height: number };
		source?: string;
		data?: string;
	}[];
};

type ExportedFile = FeedbackEngine['lastExport'][number];

/** The files of the last export, as the page holds them for automation. */
export async function lastExport(page: Page) {
	const files = await page.evaluate(async () =>
		Promise.all(
			globalThis.__feedbackEngine!.lastExport.map(async (file: ExportedFile) => ({
				name: file.name,
				bytes: [...new Uint8Array(await file.blob.arrayBuffer())],
			})),
		),
	);
	return files.map(file => ({ name: file.name, bytes: Buffer.from(file.bytes) }));
}

/** Adds one item on the whole screen, exports JSON, and returns the report. */
export async function exportReport(page: Page): Promise<Report> {
	await field(page).fill('Looks off');
	await field(page).press('Enter');
	await page.getByRole('button', { name: 'Share' }).click();
	await page.getByRole('menuitem', { name: 'JSON', exact: true }).click();
	await page.getByRole('dialog', { name: 'Share JSON' }).getByRole('button', { name: 'Cancel' }).click();
	const [file] = await lastExport(page);
	return JSON.parse(file!.bytes.toString());
}

/** The tree as indented titles, with each component's source. */
export function outline(report: Report, layer?: number) {
	const depth = new Map<number, number>();
	return report.nodes
		.map(node => {
			depth.set(node.id, node.parent === undefined ? 0 : depth.get(node.parent)! + 1);
			return node;
		})
		.filter(node => layer === undefined || node.layer === layer)
		.map(node => {
			const title = node.label ? `${node.name} "${node.label}"` : node.name;
			return `${'  '.repeat(depth.get(node.id)!)}${title}${node.kind === 'component' ? `  ${node.source}` : ''}`;
		});
}

/** The capture the editor shows, as PNG bytes. */
export async function captureImage(page: Page) {
	const data = await page.evaluate(() =>
		document.querySelector('[data-feedback-engine]')!.shadowRoot!.querySelector('canvas')!.toDataURL('image/png'),
	);
	return Buffer.from(data.split(',')[1]!, 'base64');
}

/** The share of pixels that differ between a region of the capture and the browser's own screenshot of the window. */
export function difference(capture: Buffer, window: Buffer, top: number) {
	const whole = PNG.sync.read(capture);
	const real = PNG.sync.read(window);
	const region = new PNG({ width: real.width, height: real.height });
	PNG.bitblt(whole, region, 0, top, real.width, real.height, 0, 0);
	const changed = pixelmatch(region.data, real.data, undefined, real.width, real.height, { threshold: 0.1 });
	return changed / (real.width * real.height);
}
