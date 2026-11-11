export type Point = { x: number; y: number };
export type Size = { width: number; height: number };
export type Frame = Point & Size;

export type NodeKind = 'screen' | 'layer' | 'component' | 'element';

export type Node = {
	id: number;
	parent: number | null;
	/** 0 for the base screen. Higher layers are presented on top. */
	layer: number;
	kind: NodeKind;
	/** Component name, layer name, or element role. */
	name: string;
	/** Visible text of an element. */
	label?: string;
	frame: Frame;
	/** `file:line`. Components always have one. Elements have one where the framework records it. */
	source?: string;
	data?: string;
};

export type ContextEntry = { name: string; value: string };

export type Capture = {
	date: Date;
	/** Size of the whole capture, taller than the window when the page scrolls. */
	size: Size;
	/** The part of the capture that was on screen when it was taken. */
	visible: Frame;
	/** Indexed by `Node.id`. Node 0 is the whole capture. */
	nodes: Node[];
	environment: ContextEntry[];
	context: ContextEntry[];
	screenName?: string;
};

export const contains = (frame: Frame, point: Point) =>
	point.x >= frame.x && point.x < frame.x + frame.width && point.y >= frame.y && point.y < frame.y + frame.height;

export const area = (frame: Frame) => frame.width * frame.height;

export const title = (node: Node) => (node.label ? `${node.name} "${node.label}"` : node.name);

/** The node and its ancestors, from the node itself up to the screen. */
export function pathFrom(capture: Capture, id: number): Node[] {
	const path: Node[] = [];
	for (let current: number | null = id; current !== null; current = capture.nodes[current]!.parent) {
		path.push(capture.nodes[current]!);
	}
	return path;
}

export function childrenOf(capture: Capture): number[][] {
	const children: number[][] = capture.nodes.map(() => []);
	for (const node of capture.nodes) if (node.parent !== null) children[node.parent]!.push(node.id);
	return children;
}

export function depthsOf(capture: Capture): number[] {
	const depths = capture.nodes.map(() => 0);
	for (const node of capture.nodes) if (node.parent !== null) depths[node.id] = depths[node.parent]! + 1;
	return depths;
}

/** Picks the most specific node under a point. Only the topmost layer covering the point competes, so a dialog hides the page it covers. */
export function hitTest(capture: Capture, point: Point): number {
	const layer = Math.max(
		0,
		...capture.nodes.filter(node => node.kind === 'layer' && contains(node.frame, point)).map(node => node.layer),
	);
	const depths = depthsOf(capture);
	let best: Node | undefined;
	for (const node of capture.nodes) {
		if (node.layer !== layer || node.kind === 'screen' || !contains(node.frame, point)) continue;
		if (
			!best ||
			area(node.frame) < area(best.frame) ||
			(area(node.frame) === area(best.frame) && depths[node.id]! > depths[best.id]!)
		) {
			best = node;
		}
	}
	return best?.id ?? 0;
}

/** Two nodes are the same kind of thing when they are the same component tag or the same element role. */
const sameKind = (a: Node, b: Node) =>
	a.kind === b.kind && (a.kind === 'component' ? a.source === b.source : a.kind !== 'element' || a.name === b.name);

/**
 * Nodes that play the same part as `id` in sibling components, such as the same button in every row of a list.
 * Siblings are components with the same tag as a component on the node's path and the same enclosing component.
 * Inside each, the node is found by walking down the same kinds at the same positions. The nearest component with
 * siblings wins, so a tagged part inside a repeated row matches its copies in the other rows.
 */
export function similar(capture: Capture, id: number): number[] {
	const path = pathFrom(capture, id);
	const children = childrenOf(capture);
	const enclosing = (node: number) =>
		pathFrom(capture, node)
			.slice(1)
			.find(above => above.kind !== 'element')?.id;
	for (const [anchor, component] of path.entries()) {
		if (component.kind !== 'component') continue;
		const context = enclosing(component.id);
		const steps = path.slice(0, anchor).map(node => ({
			node,
			index: children[node.parent!]!.filter(sibling => sameKind(capture.nodes[sibling]!, node)).indexOf(node.id),
		}));
		const matches: number[] = [];
		for (const sibling of capture.nodes) {
			if (sibling.id === component.id || !sameKind(sibling, component) || enclosing(sibling.id) !== context) continue;
			let current: number | undefined = sibling.id;
			for (const step of steps.toReversed()) {
				if (current === undefined) break;
				current = children[current]!.filter(child => sameKind(capture.nodes[child]!, step.node))[step.index];
			}
			if (current !== undefined) matches.push(current);
		}
		if (matches.length) return matches;
	}
	return [];
}

/** The `file:line` an item on this node points an agent at: its own, or the nearest one above it. */
export function nearestSource(capture: Capture, id: number): string | undefined {
	return pathFrom(capture, id).find(node => node.source)?.source;
}

export function nearestComponent(capture: Capture, id: number): Node | undefined {
	return pathFrom(capture, id).find(node => node.kind === 'component');
}
