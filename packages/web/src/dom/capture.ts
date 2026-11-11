import { buildTree, contextLimit, describe, type Capture, type ContextEntry } from '../core/index.ts';
import { readScene } from './scene.ts';
import { captureScale, screenshot } from './screenshot.ts';

export type Screen = { capture: Capture; image: HTMLCanvasElement; scale: number };

export type CaptureOptions = {
	app?: string;
	version?: string;
	context: { name: string; value: () => unknown }[];
};

function browser() {
	const brands = (
		navigator as Navigator & { userAgentData?: { brands: { brand: string; version: string }[]; platform: string } }
	).userAgentData;
	const brand = brands?.brands.find(entry => !/not.?a.?brand|chromium/i.test(entry.brand));
	if (brand) return `${brand.brand} ${brand.version} · ${brands!.platform}`;
	const agent = navigator.userAgent;
	const match =
		/(Firefox|Edg|Chrome)\/(\d+)/.exec(agent) ?? (/Version\/(\d+).*Safari/.exec(agent) && ['', 'Safari', RegExp.$1]);
	const platform = /iPhone|iPad|Android|Mac OS X|Windows|Linux/.exec(agent)?.[0] ?? navigator.platform;
	return match ? `${match[1] === 'Edg' ? 'Edge' : match[1]} ${match[2]} · ${platform}` : agent;
}

function environment(options: CaptureOptions, date: Date): ContextEntry[] {
	const entries: (ContextEntry | false | undefined)[] = [
		{ name: 'App', value: options.app ?? (document.title || location.hostname) },
		{ name: 'Location', value: `${location.pathname}${location.search}${location.hash}` },
		options.version !== undefined && { name: 'Version', value: options.version },
		{ name: 'Device', value: browser() },
		{
			name: 'Display',
			value: `${innerWidth} × ${innerHeight} px @${Math.round(devicePixelRatio * 100) / 100}x · ${matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'} mode`,
		},
		{ name: 'Captured', value: date.toISOString().replace(/\.\d+Z$/, 'Z') },
		{ name: 'Locale', value: navigator.language },
	];
	return entries.filter(entry => !!entry);
}

/**
 * Reads the page and draws it, at the moment of the trigger. The window scrolls to its origin while the page is read,
 * so a sticky bar is where the screenshot draws it, and then returns to where it was.
 */
export async function captureScreen(options: CaptureOptions): Promise<Screen> {
	const date = new Date();
	const scroll = { x: scrollX, y: scrollY };
	const context = options.context.flatMap(({ name, value }) => {
		try {
			return [{ name, value: describe(value(), contextLimit) ?? '' }];
		} catch (error) {
			console.warn(`Feedback could not read the context ${name}`, error);
			return [];
		}
	});
	// Reading and scrolling back happen in one task, so the browser never paints the jump.
	const moved = scroll.x !== 0 || scroll.y !== 0;
	if (moved) scrollTo({ left: 0, top: 0, behavior: 'instant' });
	const scene = readScene(scroll);
	if (moved) scrollTo({ left: scroll.x, top: scroll.y, behavior: 'instant' });

	const visible = { x: scroll.x, y: scroll.y, width: innerWidth, height: innerHeight };
	const scale = captureScale(scene.size);
	return {
		capture: {
			date,
			size: scene.size,
			visible,
			nodes: buildTree(scene),
			environment: environment(options, date),
			context,
			screenName: document.title || undefined,
		},
		image: await screenshot(scene.size, scale, visible, scene.fixed),
		scale,
	};
}
