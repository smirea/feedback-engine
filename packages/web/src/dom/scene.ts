import { computeAccessibleName, getRole } from 'dom-accessibility-api';
import { describe, type Frame, type Point, type RawNode, type RawScene } from '../core/index.ts';
import { discovery, hostAttribute, sourceAttribute, tags, type Component } from './tags.ts';

/** Roles whose content merges into one element, as VoiceOver reads a button as one stop. */
const controls: Record<string, string> = {
	button: 'Button',
	link: 'Link',
	switch: 'Switch',
	checkbox: 'Checkbox',
	radio: 'Radio button',
	textbox: 'Text field',
	searchbox: 'Search field',
	combobox: 'Combo box',
	listbox: 'List box',
	slider: 'Slider',
	spinbutton: 'Stepper',
	tab: 'Tab',
	option: 'Option',
	menuitem: 'Menu item',
	menuitemcheckbox: 'Menu item',
	menuitemradio: 'Menu item',
	heading: 'Header',
	img: 'Image',
	progressbar: 'Progress',
	meter: 'Meter',
};

const skipped = new Set(['SCRIPT', 'STYLE', 'TEMPLATE', 'NOSCRIPT', 'HEAD', 'LINK', 'META', 'TITLE', 'BR', 'WBR']);
const leaves = new Set([
	'svg',
	'CANVAS',
	'VIDEO',
	'AUDIO',
	'IFRAME',
	'OBJECT',
	'EMBED',
	'SELECT',
	'TEXTAREA',
	'INPUT',
	'IMG',
]);

type SvelteElement = Element & { __svelte_meta?: { loc?: { file: string; line: number } } };

/** A root of content that stays put while the page scrolls: a `position: fixed` element, a modal dialog, or an open popover. */
export type FixedRoot = { element: HTMLElement; frame: Frame; layer: number; backdrop?: string };

export type Scene = RawScene & { fixed: FixedRoot[] };

const union = (a: Frame, b: Frame): Frame => {
	const x = Math.min(a.x, b.x);
	const y = Math.min(a.y, b.y);
	return {
		x,
		y,
		width: Math.max(a.x + a.width, b.x + b.width) - x,
		height: Math.max(a.y + a.height, b.y + b.height) - y,
	};
};

const intersect = (a: Frame, b: Frame): Frame => {
	const x = Math.max(a.x, b.x);
	const y = Math.max(a.y, b.y);
	return {
		x,
		y,
		width: Math.max(0, Math.min(a.x + a.width, b.x + b.width) - x),
		height: Math.max(0, Math.min(a.y + a.height, b.y + b.height) - y),
	};
};

function layerRoots(): Element[] {
	const roots = new Set<Element>();
	for (const selector of ['dialog:modal', '[popover]:popover-open', '[aria-modal="true"]']) {
		try {
			for (const element of document.querySelectorAll(selector)) roots.add(element);
		} catch {
			// A browser without this selector has no such layer to find.
		}
	}
	return [...roots].filter(root => !root.closest(`[${hostAttribute}]`));
}

function layerName(root: Element) {
	const role = root.getAttribute('role');
	if (role === 'alertdialog') return 'Alert';
	if (role === 'menu' || root.querySelector(':scope > [role="menu"]')) return 'Menu';
	return root.tagName === 'DIALOG' || role === 'dialog' ? 'Dialog' : 'Popover';
}

const normalized = (value: string | null | undefined) => (value ?? '').replace(/\s+/g, ' ').trim();

const isControl = (element: Element) => leaves.has(element.tagName) || (getRole(element) ?? '') in controls;

/**
 * The words of a text and of the formatting inside it. A control inside it, such as the field a label wraps, is its own
 * element. Neighboring text nodes join as they are, since React writes `{count}%` as two of them.
 */
function text(element: Element): string {
	let words = '';
	for (const child of element.childNodes) {
		if (child.nodeType === Node.TEXT_NODE) words += child.textContent ?? '';
		else if (child instanceof Element && !isControl(child)) words += ` ${text(child)} `;
	}
	return normalized(words);
}

function label(element: Element, role: string) {
	const name = normalized(computeAccessibleName(element));
	if (element instanceof HTMLInputElement && (element.type === 'checkbox' || element.type === 'radio')) {
		return [name, element.checked ? 'on' : 'off'].filter(Boolean).join(', ');
	}
	if (role === 'switch' || role === 'checkbox' || role === 'radio') {
		return [name, element.getAttribute('aria-checked') === 'true' ? 'on' : 'off'].filter(Boolean).join(', ');
	}
	if (element instanceof HTMLSelectElement) {
		return [name, normalized(element.selectedOptions[0]?.textContent)].filter(Boolean).join(', ');
	}
	if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
		const value = element instanceof HTMLInputElement && element.type === 'password' ? '' : element.value;
		return [name, value].filter(Boolean).join(', ') || element.placeholder;
	}
	return name;
}

/**
 * Reads the page into a scene. Frames are in capture coordinates: the document's, with content that stays put while
 * the page scrolls placed over the part that was on screen. Call it with the window scrolled to its origin, so a
 * sticky bar sits where the screenshot draws it, and pass the scroll position the user had as `scroll`.
 */
export function readScene(scroll: Point): Scene {
	const root = document.documentElement;
	const size = { width: Math.max(root.scrollWidth, innerWidth), height: Math.max(root.scrollHeight, innerHeight) };
	const roots = layerRoots();
	const scene: Scene = { size, layers: [{ name: 'Screen', frame: { x: 0, y: 0, ...size } }], nodes: [], fixed: [] };

	type Walk = {
		parent: number | null;
		layer: number;
		clip: Frame | undefined;
		/** `text` inside a text, whose own words are already in its label. `all` inside a control or hidden content, where only tagged components still become nodes. */
		merged: 'none' | 'text' | 'all';
		fixed: boolean;
	};

	const frameOf = (element: Element, fixed: boolean): Frame => {
		const rect = element.getBoundingClientRect();
		return {
			x: rect.x + (fixed ? scroll.x : 0),
			y: rect.y + (fixed ? scroll.y : 0),
			width: rect.width,
			height: rect.height,
		};
	};

	let discovered: Map<Element, Component[]> | undefined;
	try {
		discovered = discovery.read?.();
	} catch (error) {
		// The reader depends on a framework's internals. Without it the capture still has the elements and the tags.
		console.warn("Feedback could not read the framework's components", error);
	}
	/** Where each component already is, by its roots and then by layer. Its later roots in that layer grow the same node. */
	const placed = new Map<Element[], Map<number, number>>();

	/** The components rooted at an element, outermost first: the ones the framework knows, then the element's own tag. */
	const componentsAt = (element: Element, isLayer: boolean): Component[] => {
		// A dialog or a menu is one root of the screen that opens it. That screen is not the layer, so only a component that draws nothing else is.
		const found = (discovered?.get(element) ?? []).filter(component => !isLayer || component.roots.length === 1);
		const tag = tags.get(element);
		if (!tag) return found;
		// A tag that repeats the name of a component rooted here adds data to it, such as state the framework does not expose.
		const same = found.findLastIndex(component => component.tag.name === tag.name);
		if (same === -1) return [...found, { tag, roots: [element] }];
		const known = found[same]!;
		return found.with(same, { tag: { ...known.tag, data: tag.data ?? known.tag.data }, roots: known.roots });
	};

	const add = (node: Omit<RawNode, 'frame'>, frame: Frame, clip: Frame | undefined) => {
		const clipped = clip ? intersect(frame, clip) : frame;
		if (!clipped.width || !clipped.height) return null;
		scene.nodes.push({ ...node, frame: clipped });
		return scene.nodes.length - 1;
	};

	const visit = (element: Element, walk: Walk) => {
		if (skipped.has(element.tagName) || element.hasAttribute(hostAttribute)) return;
		const style = getComputedStyle(element);
		if (style.display === 'none' || Number(style.opacity) === 0) return;

		let { parent, layer, clip, merged, fixed } = walk;
		const isLayer = roots.includes(element);
		if (style.position === 'fixed' || isLayer) {
			// A layer is its own root even inside a fixed shell or another layer: the browser lifts it to the top layer.
			if (isLayer) {
				const frame = frameOf(element, true);
				layer = scene.layers.length;
				scene.layers.push({ name: layerName(element), frame });
				scene.fixed.push({
					element: element as HTMLElement,
					frame,
					layer,
					backdrop: getComputedStyle(element, '::backdrop').backgroundColor,
				});
				parent = null;
				merged = 'none';
			} else if (!fixed) {
				scene.fixed.push({ element: element as HTMLElement, frame: frameOf(element, true), layer });
			}
			fixed = true;
			clip = undefined;
		}

		const frame = frameOf(element, fixed);
		const visible = style.visibility === 'visible';
		const hidden = merged === 'all' || element.getAttribute('aria-hidden') === 'true' || element.hasAttribute('inert');
		const location = (element as SvelteElement).__svelte_meta?.loc;
		const source = location
			? `${location.file}:${location.line}`
			: (element.getAttribute(sourceAttribute) ?? undefined);

		for (const component of visible ? componentsAt(element, isLayer) : []) {
			const { tag } = component;
			const layers = placed.get(component.roots) ?? new Map<number, number>();
			placed.set(component.roots, layers);
			const index = layers.get(layer);
			if (index !== undefined) {
				const clipped = clip ? intersect(frame, clip) : frame;
				if (clipped.width && clipped.height) scene.nodes[index]!.frame = union(scene.nodes[index]!.frame, clipped);
				parent = index;
				continue;
			}
			let data: string | undefined;
			try {
				data = tag.data ? describe(tag.data()) : undefined;
			} catch (error) {
				console.warn(`Feedback could not read the data of ${tag.name}`, error);
			}
			const added = add({ parent, layer, kind: 'component', name: tag.name, source: tag.source, data }, frame, clip);
			if (added === null) continue;
			layers.set(layer, added);
			parent = added;
		}

		if (visible && !hidden) {
			const role = getRole(element) ?? '';
			const native = element.tagName === 'INPUT' || element.tagName === 'SELECT' || element.tagName === 'TEXTAREA';
			const name = controls[role] ?? (native ? 'Text field' : undefined);
			const ownText =
				merged === 'none' &&
				[...element.childNodes].some(child => child.nodeType === Node.TEXT_NODE && child.textContent?.trim());
			if (name || ownText) {
				const found = add(
					{
						parent,
						layer,
						kind: 'element',
						name: name ?? 'Text',
						label: name ? label(element, role) : text(element),
						source,
					},
					frame,
					clip,
				);
				if (found !== null) parent = found;
				merged = name ? 'all' : 'text';
			}
		} else if (hidden) {
			merged = 'all';
		}

		if (leaves.has(element.tagName)) return;
		if (
			element !== root &&
			element !== document.body &&
			(style.overflowX !== 'visible' || style.overflowY !== 'visible')
		) {
			clip = clip ? intersect(clip, frame) : frame;
		}
		for (const child of element.children) visit(child, { parent, layer, clip, merged, fixed });
	};

	visit(document.body, { parent: null, layer: 0, clip: undefined, merged: 'none', fixed: false });
	return scene;
}
