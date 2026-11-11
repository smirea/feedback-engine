import type { Frame, Node, Size } from './model.ts';

/** What a platform reads off the live page, before it becomes a numbered tree. */
export type RawNode = {
	/** Index of the nearest node above it in `RawScene.nodes`, or `null` directly under its layer. */
	parent: number | null;
	layer: number;
	kind: 'component' | 'element';
	name: string;
	label?: string;
	frame: Frame;
	source?: string;
	data?: string;
};

export type RawScene = {
	size: Size;
	/** Index 0 is the base screen. Later layers are presented on top of earlier ones. */
	layers: { name: string; frame: Frame }[];
	nodes: RawNode[];
};

const usable = (frame: Frame) =>
	frame.width > 0 &&
	frame.height > 0 &&
	[frame.x, frame.y, frame.width, frame.height].every(value => Number.isFinite(value) && Math.abs(value) < 100_000);

const intersects = (a: Frame, b: Frame) =>
	a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;

const covers = (outer: Frame, inner: Frame) =>
	outer.x <= inner.x &&
	outer.y <= inner.y &&
	outer.x + outer.width >= inner.x + inner.width &&
	outer.y + outer.height >= inner.y + inner.height;

function clip(frame: Frame, bounds: Frame): Frame {
	const x = Math.max(frame.x, bounds.x);
	const y = Math.max(frame.y, bounds.y);
	return {
		x,
		y,
		width: Math.min(frame.x + frame.width, bounds.x + bounds.width) - x,
		height: Math.min(frame.y + frame.height, bounds.y + bounds.height) - y,
	};
}

type Entry = Omit<Node, 'id'>;

/**
 * Numbers the scene depth-first in reading order, so every parent precedes its children. No tap can reach what a
 * higher layer covers completely, so the tree leaves it out. Children of a node that is left out move to the nearest
 * node above it that stays. Frames are clipped to the capture, so nothing reports a position outside the image.
 */
export function buildTree(scene: RawScene): Node[] {
	const screen = { x: 0, y: 0, ...scene.size };
	const upper = scene.layers
		.map((layer, index) => ({ index, frame: layer.frame }))
		.slice(1)
		.filter(layer => usable(layer.frame));
	const shown = (frame: Frame, layer: number) =>
		usable(frame) &&
		intersects(frame, screen) &&
		!upper.some(cover => cover.index > layer && covers(cover.frame, frame));

	const entries: Entry[] = [{ parent: null, layer: 0, kind: 'screen', name: 'Screen', frame: screen }];
	const layerEntry = [0];
	for (const [index, layer] of scene.layers.entries()) {
		if (index === 0) continue;
		if (!shown(layer.frame, index)) {
			layerEntry.push(0);
			continue;
		}
		layerEntry.push(entries.length);
		entries.push({ parent: 0, layer: index, kind: 'layer', name: layer.name, frame: layer.frame });
	}

	const entryOf: (number | undefined)[] = [];
	for (const [index, raw] of scene.nodes.entries()) {
		if (!shown(raw.frame, raw.layer)) continue;
		let above = raw.parent;
		while (above !== null && (entryOf[above] === undefined || scene.nodes[above]!.layer !== raw.layer)) {
			above = scene.nodes[above]!.parent;
		}
		entryOf[index] = entries.length;
		entries.push({
			parent: above === null ? layerEntry[raw.layer]! : entryOf[above]!,
			layer: raw.layer,
			kind: raw.kind,
			name: raw.name,
			label: raw.label || undefined,
			frame: raw.frame,
			source: raw.source,
			data: raw.data,
		});
	}

	const children: number[][] = entries.map(() => []);
	for (const [index, entry] of entries.entries()) if (entry.parent !== null) children[entry.parent]!.push(index);
	const nodes: Node[] = [];
	const visit = (index: number, parent: number | null) => {
		const entry = entries[index]!;
		const id = nodes.length;
		nodes.push({ ...entry, id, parent, frame: clip(entry.frame, screen) });
		const ordered = children[index]!.toSorted((a, b) => {
			const first = entries[a]!;
			const second = entries[b]!;
			if (first.layer !== second.layer) return first.layer - second.layer;
			return Math.abs(first.frame.y - second.frame.y) > 0.5
				? first.frame.y - second.frame.y
				: first.frame.x - second.frame.x;
		});
		for (const child of ordered) visit(child, id);
	};
	visit(0, null);
	return nodes;
}

/**
 * Where a capture that reaches its height limit should end: the lowest y from `floor` down to `limit` that no frame
 * crosses, so the last row is whole. `undefined` when frames cover the whole range.
 */
export function cut(limit: number, floor: number, frames: Frame[]): number | undefined {
	const candidates = [
		limit,
		...frames.flatMap(frame => [frame.y, frame.y + frame.height]).filter(y => y > floor && y < limit),
	];
	return candidates
		.toSorted((a, b) => b - a)
		.find(y => !frames.some(frame => frame.y < y - 0.5 && frame.y + frame.height > y + 0.5));
}
