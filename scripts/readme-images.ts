#!/usr/bin/env bun
/**
 * Retakes the web images in the READMEs, `docs/web-editor.png` and `docs/web-export.png`, from the React example in
 * Google Chrome: four notes on the Lists screen, the fourth referencing the New List button. Needs `pngquant`.
 */
import { $ } from 'bun';
import { spawn } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { chromium, type Page } from 'playwright';
import env from '../env.ts';

const root = join(import.meta.dir, '..');
const editor = (page: Page) => page.getByRole('dialog', { name: 'Feedback', exact: true });
const canvas = (page: Page) => page.getByRole('img', { name: /^Screenshot/ });
const field = (page: Page) => page.getByRole('textbox', { name: 'Feedback text' });

async function present(page: Page) {
	await page.evaluate(() => globalThis.__feedbackEngine!.present());
	await editor(page).waitFor();
}

/** Clicks the screenshot at a point given in the captured page's own coordinates. */
async function tap(page: Page, x: number, y: number) {
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

/** The files of the last export, as the page holds them for automation. */
async function lastExport(page: Page) {
	const files = await page.evaluate(async () =>
		Promise.all(
			globalThis.__feedbackEngine!.lastExport.map(async file => ({
				name: file.name,
				bytes: [...new Uint8Array(await file.blob.arrayBuffer())],
			})),
		),
	);
	return files.map(file => ({ name: file.name, bytes: Buffer.from(file.bytes) }));
}

const center = async (locator: ReturnType<Page['locator']>) => {
	const box = (await locator.boundingBox())!;
	return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
};

const port = env.UI_PORT + 8;
const server = spawn(
	'bun',
	[
		'--env-file=../../.env',
		'--env-file=../../.env.local',
		'--bun',
		'vite',
		'--host',
		'127.0.0.1',
		'--port',
		String(port),
		'--strictPort',
	],
	{ cwd: join(root, 'examples/todo-react'), stdio: 'ignore' },
);
const browser = await chromium.launch({ channel: 'chrome' });

try {
	for (let attempt = 0; ; attempt++) {
		if (
			await fetch(`http://127.0.0.1:${port}/`).then(
				response => response.ok,
				() => false,
			)
		)
			break;
		if (attempt === 150) throw new Error('The React example did not start');
		await Bun.sleep(100);
	}
	const page = await browser.newPage({
		viewport: { width: 900, height: 600 },
		deviceScaleFactor: 2,
		colorScheme: 'dark',
	});
	await page.goto(`http://127.0.0.1:${port}/`);
	await page.getByRole('heading', { level: 1 }).waitFor();

	const groceries = await center(page.getByRole('link', { name: /Groceries/ }));
	const open = await center(page.getByText('21', { exact: true }));
	const header = await center(page.getByRole('heading', { name: 'My Lists' }));
	const settings = await center(page.getByRole('link', { name: 'Settings' }));
	const newList = await center(page.getByRole('button', { name: 'New List' }));

	await present(page);
	const note = async (at: { x: number; y: number }, text: string) => {
		await tap(page, at.x, at.y);
		await field(page).fill(text);
		await field(page).press('Enter');
	};
	await note(groceries, 'Show a progress bar here');
	await note(open, 'Make this count tappable');
	await note(header, 'Too faint to read');
	await tap(page, settings.x, settings.y);
	await field(page).fill('Move this next to @');
	await tap(page, newList.x, newList.y);
	await page.getByRole('button', { name: 'Insert' }).click();
	await field(page).press('Enter');

	await page.getByRole('button', { name: 'Share' }).click();
	await page.getByRole('menuitem', { name: 'Image', exact: true }).click();
	await page.getByRole('dialog', { name: 'Share Image' }).getByRole('button', { name: 'Cancel' }).click();
	const [image] = await lastExport(page);
	writeFileSync(join(root, 'docs/web-export.png'), image!.bytes);

	await tap(page, groceries.x, groceries.y);
	await canvas(page).evaluate(node => node.parentElement!.scrollTo(0, 0));
	await page.mouse.move(0, 0);
	await page.screenshot({ path: join(root, 'docs/web-editor.png') });
	// The READMEs show both far smaller, so fewer pixels and a palette stay sharp at a fraction of the bytes.
	for (const [name, size] of [
		['web-editor.png', 1200],
		['web-export.png', 2000],
	] as const) {
		const file = join(root, 'docs', name);
		await $`sips -Z ${size} ${file}`.quiet();
		await $`pngquant --quality 80-95 --skip-if-larger --force --ext .png ${file}`;
	}
} finally {
	await browser.close();
	server.kill();
}
