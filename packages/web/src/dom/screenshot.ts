import { createContext, destroyContext, domToForeignObjectSvg, loadMedia, type Options } from 'modern-screenshot';
import type { Frame, Point, Size } from '../core/index.ts';
import type { FixedRoot } from './scene.ts';
import { hostAttribute } from './tags.ts';

/** iOS Safari refuses a larger canvas. */
const pixelBudget = 16_000_000;
const maxSide = 16_384;

/** The largest scale up to `wanted` at which `size` fits one canvas. */
export function canvasScale(size: Size, wanted: number) {
	return Math.min(
		wanted,
		Math.sqrt(pixelBudget / (size.width * size.height)),
		maxSide / size.width,
		maxSide / size.height,
	);
}

/** One copy of the DOM as an SVG image, at its place in the capture, after `backdrop` covers the part that was on screen. */
type Part = { image?: HTMLImageElement; frame: Frame; backdrop?: { color: string; frame: Frame } };

const intersect = (a: Frame, b: Frame): Frame | undefined => {
	const x = Math.max(a.x, b.x);
	const y = Math.max(a.y, b.y);
	const width = Math.min(a.x + a.width, b.x + b.width) - x;
	const height = Math.min(a.y + a.height, b.y + b.height) - y;
	return width > 0 && height > 0 ? { x, y, width, height } : undefined;
};

/**
 * The frozen page, kept as vector copies of the DOM, so any part of it can be drawn sharp at any scale long after the
 * page moved on: the editor draws what is in view at the screen's resolution, and an export draws at its own.
 */
export class Picture {
	constructor(
		readonly size: Size,
		private readonly parts: Part[],
	) {}

	/**
	 * Draws `region` of the capture into `context` with its corner at `at` and `scale` units per point. Each copy is
	 * drawn only where it meets the region, so the browser rasterizes no more of it than shows.
	 */
	draw(context: CanvasRenderingContext2D, region: Frame, at: Point, scale: number) {
		const place = (frame: Frame) => ({
			x: at.x + (frame.x - region.x) * scale,
			y: at.y + (frame.y - region.y) * scale,
			width: frame.width * scale,
			height: frame.height * scale,
		});
		for (const { image, frame, backdrop } of this.parts) {
			const tinted = backdrop && intersect(backdrop.frame, region);
			if (tinted) {
				const target = place(tinted);
				context.fillStyle = backdrop.color;
				context.fillRect(target.x, target.y, target.width, target.height);
			}
			const shown = image && intersect(frame, region);
			if (!shown) continue;
			const target = place(shown);
			context.drawImage(
				image,
				shown.x - frame.x,
				shown.y - frame.y,
				shown.width,
				shown.height,
				target.x,
				target.y,
				target.width,
				target.height,
			);
		}
	}

	/** The whole capture on a canvas, at `scale` or as close to it as one canvas allows. */
	canvas(scale: number) {
		const fitted = canvasScale(this.size, scale);
		const canvas = document.createElement('canvas');
		canvas.width = Math.round(this.size.width * fitted);
		canvas.height = Math.round(this.size.height * fitted);
		this.draw(canvas.getContext('2d')!, { x: 0, y: 0, ...this.size }, { x: 0, y: 0 }, fitted);
		return canvas;
	}
}

/**
 * Copies the page, from `top` down `size.height` points. The browser gives a page no way to read its own pixels, so the
 * DOM is copied into an SVG image. The document goes first, without the content that stays put while the page
 * scrolls. Each such root is then copied on its own and drawn where it was on screen, over a modal's backdrop, which a
 * copy of the DOM leaves out. `visible` and the roots' frames are in capture coordinates.
 */
export function takePicture(size: Size, top: number, visible: Frame, fixed: FixedRoot[]) {
	return withFieldState(() => copy(size, top, visible, fixed));
}

/**
 * The copy carries attributes, and what a field holds is a property. This writes the text of each text area and the
 * state of each checkbox and radio button into their attributes while `work` runs, then puts the attributes back.
 */
async function withFieldState<T>(work: () => Promise<T>) {
	const restore: (() => void)[] = [];
	for (const field of document.querySelectorAll('textarea, input[type="checkbox"], input[type="radio"]')) {
		if (field instanceof HTMLTextAreaElement) {
			const before = field.textContent;
			if (before === field.value) continue;
			field.textContent = field.value;
			restore.push(() => (field.textContent = before));
		} else if (field instanceof HTMLInputElement && field.hasAttribute('checked') !== field.checked) {
			field.toggleAttribute('checked', field.checked);
			restore.push(() => field.toggleAttribute('checked', !field.checked));
		}
	}
	try {
		return await work();
	} finally {
		for (const undo of restore) undo();
	}
}

/**
 * What the browser paints behind the page: the root's background, else the body's, which the root takes over, else the
 * canvas color of the page's color scheme. The copy is transparent where the page sets no background.
 */
function pageBackground() {
	for (const element of [document.documentElement, document.body]) {
		const color = element && getComputedStyle(element).backgroundColor;
		if (color && color !== 'transparent' && color !== 'rgba(0, 0, 0, 0)') return color;
	}
	const probe = document.createElement('div');
	probe.style.cssText = 'position: fixed; background: Canvas';
	document.documentElement.append(probe);
	const color = getComputedStyle(probe).backgroundColor;
	probe.remove();
	return color;
}

/** What modern-screenshot's `svgToDataUrl` does, which it does not export. */
function svgImageURL(svg: SVGElement) {
	// XML 1.0 has no place for control characters or lone surrogates, and a page's text can hold them.
	// oxlint-disable-next-line no-control-regex
	const invalid = /[\u0000-\u0008\v\f\u000E-\u001F\uD800-\uDFFF\uFFFE\uFFFF]/gu;
	const markup = new XMLSerializer().serializeToString(svg).replace(invalid, '');
	return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(markup)}`;
}

/**
 * Copies `node` into a decoded SVG image. modern-screenshot draws a copy with images again after an interval, for
 * browsers that decode the images inside an SVG image only once it is first drawn. It waits once per image, which held
 * Safari 2.4 s on a page with 20 icons, so the copy is drawn once and waits one interval in all.
 */
async function svgImage(node: Element, options: Options) {
	// modern-screenshot leaves a scrolled container's copy at its top unless `restoreScrollPosition` is on, which shifts
	// the children of a scrolled element by its scroll. The window's scroll is the root's, and the copy of the document
	// must start at its top, so the shift is taken back off the root's children.
	const transforms = new WeakMap<Node, string>();
	const scrolledRoot = node === document.scrollingElement && (node.scrollTop !== 0 || node.scrollLeft !== 0);
	const context = await createContext(node, {
		...options,
		features: { restoreScrollPosition: true },
		onCloneEachNode: scrolledRoot
			? clone => void (clone instanceof HTMLElement && transforms.set(clone, clone.style.transform))
			: undefined,
		onCloneNode: scrolledRoot
			? clone => {
					for (const child of (clone as HTMLElement).children as HTMLCollectionOf<HTMLElement>) {
						const transform = transforms.get(child);
						if (transform !== undefined) child.style.transform = transform;
					}
				}
			: undefined,
	});
	try {
		const svg = await domToForeignObjectSvg(context);
		const image = await loadMedia(svgImageURL(svg), { timeout: context.timeout });
		if (context.drawImageCount > 0) {
			document.createElement('canvas').getContext('2d')!.drawImage(image, 0, 0, 1, 1);
			await new Promise(resolve => setTimeout(resolve, context.drawImageInterval));
		}
		return image;
	} finally {
		destroyContext(context);
	}
}

async function copy(size: Size, top: number, visible: Frame, fixed: FixedRoot[]) {
	const roots = new Set<Node>(fixed.map(root => root.element));
	const parts: Part[] = [
		{
			image: await svgImage(document.documentElement, {
				width: size.width,
				height: top + size.height,
				backgroundColor: pageBackground(),
				filter: node => !(roots.has(node) || (node instanceof Element && node.hasAttribute(hostAttribute))),
			}),
			frame: { x: 0, y: -top, width: size.width, height: top + size.height },
		},
	];
	// A modal dialog or popover sits in the browser's top layer, above every other fixed root, whatever the DOM order.
	const layered = [
		...fixed.filter(root => root.backdrop === undefined),
		...fixed.filter(root => root.backdrop !== undefined),
	];
	for (const root of layered) {
		const { frame } = root;
		const backdrop = root.backdrop ? { color: root.backdrop, frame: visible } : undefined;
		const image =
			frame.width && frame.height
				? await svgImage(root.element, {
						width: frame.width,
						height: frame.height,
						// A layer inside this root is drawn by its own turn.
						filter: node => node === root.element || !roots.has(node),
						style: {
							// A copy of a popover is not open, and a closed popover is `display: none`.
							display: getComputedStyle(root.element).display,
							position: 'static',
							inset: 'auto',
							margin: '0',
							transform: 'none',
							translate: 'none',
							width: `${frame.width}px`,
							height: `${frame.height}px`,
							maxWidth: 'none',
							maxHeight: 'none',
						},
					})
				: undefined;
		parts.push({ image, frame, backdrop });
	}
	return new Picture(size, parts);
}
