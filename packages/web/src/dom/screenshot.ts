import { domToCanvas } from 'modern-screenshot';
import type { Frame, Size } from '../core/index.ts';
import type { FixedRoot } from './scene.ts';
import { hostAttribute } from './tags.ts';

/** iOS Safari refuses a larger canvas, and other browsers stop at 16,384 pixels a side. */
const pixelBudget = 16_000_000;
const maxSide = 16_384;

/** The device's pixel ratio, lowered until the whole capture fits a canvas. */
export function captureScale(size: Size) {
	return Math.min(
		devicePixelRatio,
		Math.sqrt(pixelBudget / (size.width * size.height)),
		maxSide / size.width,
		maxSide / size.height,
	);
}

/**
 * Draws the page at full length. The browser gives a page no way to read its own pixels, so the DOM is drawn again
 * into a canvas. The document goes first, without the content that stays put while the page scrolls. Each such root
 * is then drawn where it was on screen, over a modal's backdrop, which a re-draw of the DOM leaves out.
 */
export function screenshot(size: Size, scale: number, visible: Frame, fixed: FixedRoot[]) {
	return withFieldState(() => draw(size, scale, visible, fixed));
}

/**
 * The re-draw copies attributes, and what a field holds is a property. This writes the text of each text area and the
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

async function draw(size: Size, scale: number, visible: Frame, fixed: FixedRoot[]) {
	const roots = new Set<Node>(fixed.map(root => root.element));
	const canvas = await domToCanvas(document.documentElement, {
		width: size.width,
		height: size.height,
		scale,
		filter: node => !(roots.has(node) || (node instanceof Element && node.hasAttribute(hostAttribute))),
	});
	// The library sizes the canvas with inline styles. The editor sizes it instead.
	canvas.removeAttribute('style');
	const context = canvas.getContext('2d')!;
	context.scale(scale, scale);
	// A modal dialog or popover sits in the browser's top layer, above every other fixed root, whatever the DOM order.
	const layered = [
		...fixed.filter(root => root.backdrop === undefined),
		...fixed.filter(root => root.backdrop !== undefined),
	];
	for (const root of layered) {
		if (root.backdrop) {
			context.fillStyle = root.backdrop;
			context.fillRect(visible.x, visible.y, visible.width, visible.height);
		}
		const { frame } = root;
		if (!frame.width || !frame.height) continue;
		const drawn = await domToCanvas(root.element, {
			width: frame.width,
			height: frame.height,
			scale,
			// A layer inside this root is drawn by its own turn.
			filter: node => node === root.element || !roots.has(node),
			style: {
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
		});
		context.drawImage(drawn, frame.x, frame.y, frame.width, frame.height);
	}
	return canvas;
}
