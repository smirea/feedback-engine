import {
	buildTree,
	captureLimit,
	captureRange,
	contextLimit,
	describe,
	type Capture,
	type ContextEntry,
	type Frame,
} from '../core/index.ts';
import { readScene, type Scene } from './scene.ts';
import { takePicture, type Picture } from './screenshot.ts';

/**
 * A capture and its picture. `image` is the whole picture on one canvas, at the screen's pixel ratio or lower when the
 * capture is too large for one, which the editor shows until it draws the part in view sharp. `pixelRatio` is the
 * screen's, the resolution an export aims for.
 */
export type Screen = { capture: Capture; picture: Picture; image: HTMLCanvasElement; pixelRatio: number };

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

/** Moves the scene up by `top` and ends it `height` points down. The tree leaves out what is outside. */
function cropped(scene: Scene, top: number, height: number): Scene {
	const up = (frame: Frame) => ({ ...frame, y: frame.y - top });
	return {
		size: { width: scene.size.width, height },
		layers: scene.layers.map((layer, index) =>
			index === 0
				? { ...layer, frame: { x: 0, y: 0, width: scene.size.width, height } }
				: { ...layer, frame: up(layer.frame) },
		),
		nodes: scene.nodes.map(node => ({ ...node, frame: up(node.frame) })),
		fixed: scene.fixed.map(root => ({ ...root, frame: up(root.frame) })),
	};
}

/**
 * Reads the page at the moment of the trigger. The window scrolls to its origin while the page is read, so a sticky
 * bar is where the picture draws it, and then returns to where it was. A page taller than iOS's limit of 16,000 pixels
 * is captured by the iOS rules, which `captureRange` holds, and `top` is where the capture starts in the document.
 */
function readPage(options: CaptureOptions) {
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
	const page = readScene(scroll);
	if (moved) scrollTo({ left: scroll.x, top: scroll.y, behavior: 'instant' });

	const { top, height } = captureRange(
		page.size.height,
		innerHeight,
		scroll.y,
		Math.floor(captureLimit / devicePixelRatio),
		page.nodes.filter(node => node.layer === 0).map(node => node.frame),
	);
	const scene = cropped(page, top, height);
	const capture: Capture = {
		date,
		size: scene.size,
		visible: { x: scroll.x, y: scroll.y - top, width: innerWidth, height: innerHeight },
		nodes: buildTree(scene),
		environment: environment(options, date),
		context,
		screenName: document.title || undefined,
	};
	return { capture, scene, top };
}

/** Reads the page without drawing it, for automation that needs only the tree. */
export const captureTree = (options: CaptureOptions) => readPage(options).capture;

/** Reads the page and copies it. */
export async function captureScreen(options: CaptureOptions): Promise<Screen> {
	const { capture, scene, top } = readPage(options);
	const picture = await takePicture(scene.size, top, capture.visible, scene.fixed);
	const pixelRatio = devicePixelRatio;
	return { capture, picture, image: picture.canvas(pixelRatio), pixelRatio };
}
