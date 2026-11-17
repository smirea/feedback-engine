import { spawn, type ChildProcess } from 'node:child_process';
import { join } from 'node:path';
import pixelmatch from 'pixelmatch';
import { chromium, webkit, type Browser, type BrowserContext, type Page } from 'playwright';
import { PNG } from 'pngjs';
import env from '../../../env.ts';

export const root = join(import.meta.dir, '../../..');

// Beside the ports `bun run dev` and `bun run dev:react` use, so the tests run while an example app is open.
const apps = {
	svelte: { folder: 'examples/todo-svelte', port: env.UI_PORT + 1 },
	react: { folder: 'examples/todo-react', port: env.UI_PORT + 6 },
};
export type AppName = keyof typeof apps;
export const appNames = Object.keys(apps) as AppName[];

export const engines = { chromium, webkit };
export type EngineName = keyof typeof engines;
export const engineNames = Object.keys(engines) as EngineName[];

const servers: ChildProcess[] = [];
const browsers = new Map<EngineName, Browser>();

export async function startServers() {
	for (const app of appNames) {
		const child = spawn(
			'bun',
			[
				'--env-file=../../.env',
				'--env-file=../../.env.local',
				'--bun',
				'vite',
				'--host',
				'127.0.0.1',
				'--port',
				String(apps[app].port),
				'--strictPort',
			],
			{ cwd: join(root, apps[app].folder), stdio: 'pipe' },
		);
		let log = '';
		child.stdout!.on('data', chunk => (log += chunk));
		child.stderr!.on('data', chunk => (log += chunk));
		servers.push(child);
		const url = `http://127.0.0.1:${apps[app].port}/`;
		for (let attempt = 0; ; attempt++) {
			if (
				await fetch(url).then(
					response => response.ok,
					() => false,
				)
			)
				break;
			if (attempt === 150) throw new Error(`The dev server of ${app} did not start:\n${log}`);
			await Bun.sleep(100);
		}
	}
}

export async function stopServers() {
	for (const browser of browsers.values()) await browser.close();
	for (const server of servers) server.kill();
}

export type Opened = { page: Page; context: BrowserContext; errors: string[] };

/** Opens a page of an example app. `errors` collects page errors and console errors, which every test expects to stay empty. */
export async function open(app: AppName, engine: EngineName, path: string): Promise<Opened> {
	if (!browsers.has(engine)) browsers.set(engine, await engines[engine].launch());
	const context = await browsers
		.get(engine)!
		.newContext({ viewport: { width: 390, height: 700 }, deviceScaleFactor: 2 });
	const page = await context.newPage();
	const errors: string[] = [];
	page.on('pageerror', error => errors.push(String(error)));
	page.on('console', message => {
		if (message.type() === 'error') errors.push(message.text());
	});
	await page.goto(`http://127.0.0.1:${apps[app].port}${path}`);
	await page.getByRole('heading', { level: 1 }).waitFor();
	return { page, context, errors };
}

export type Report = {
	size: { width: number; height: number };
	visible: { x: number; y: number; width: number; height: number };
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

/**
 * Captures the page the way the editor does, through the package's own modules as the dev server serves them to the
 * app, so the capture reads the same tags. Returns the report and the drawn screenshot as PNG bytes.
 */
export async function capture(page: Page) {
	const { json, png } = await page.evaluate(
		async folder => {
			const { captureScreen } = await import(/* @vite-ignore */ `/@fs${folder}/src/dom/capture.ts`);
			const { Annotations, reportJSON } = await import(/* @vite-ignore */ `/@fs${folder}/src/core/index.ts`);
			const screen = await captureScreen({ context: [] });
			return {
				json: reportJSON(screen.capture, new Annotations()) as string,
				png: (screen.image as HTMLCanvasElement).toDataURL('image/png'),
			};
		},
		join(root, 'packages/web'),
	);
	return { report: JSON.parse(json) as Report, image: Buffer.from(png.split(',')[1]!, 'base64') };
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

/**
 * The share of pixels that differ between the capture and the browser's own screenshot of the window, which sits `top`
 * pixels down the capture. `within` narrows both to one rectangle of the window, in pixels.
 */
export function difference(
	capture: Buffer,
	window: Buffer,
	top: number,
	within?: { x: number; y: number; width: number; height: number },
) {
	const whole = PNG.sync.read(capture);
	const real = PNG.sync.read(window);
	const area = within ?? { x: 0, y: 0, width: real.width, height: real.height };
	const drawn = new PNG({ width: area.width, height: area.height });
	const seen = new PNG({ width: area.width, height: area.height });
	PNG.bitblt(whole, drawn, area.x, top + area.y, area.width, area.height, 0, 0);
	PNG.bitblt(real, seen, area.x, area.y, area.width, area.height, 0, 0);
	const changed = pixelmatch(drawn.data, seen.data, undefined, area.width, area.height, { threshold: 0.1 });
	return changed / (area.width * area.height);
}
