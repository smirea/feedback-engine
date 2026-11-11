import type { Component } from '../dom/tags.ts';

declare global {
	/** What the Vite plugin registers: each component of the app, with its name and the `file:line` of its declaration. */
	var __feedbackComponents: WeakMap<object, [name: string, source: string]> | undefined;
}

/** The fields of a fiber, React's record of one rendered component or element. They are internal to React and have kept these names since React 17. */
type Fiber = {
	tag: number;
	type: unknown;
	elementType: unknown;
	stateNode: unknown;
	memoizedProps: unknown;
	child: Fiber | null;
	sibling: Fiber | null;
};

const portal = 4;
/** A `<title>` or `<link>` that React 19 moves to the head. It is not a part of what its component draws. */
const hoisted = 26;
/** Function, class, `forwardRef`, and `memo` components. */
const composites = new Set([0, 1, 11, 14, 15]);

const registered = (type: unknown) =>
	typeof type === 'function' || (typeof type === 'object' && type !== null)
		? globalThis.__feedbackComponents?.get(type)
		: undefined;

/** The fiber tree React shows now, for every React root on the page. A DOM node's own fiber can be the previous render's. */
function trees(): Fiber[] {
	const found: Fiber[] = [];
	for (const node of [document, ...document.querySelectorAll('*')]) {
		for (const key of Object.keys(node)) {
			if (!key.startsWith('__reactContainer$')) continue;
			found.push((node as unknown as Record<string, { stateNode: { current: Fiber } }>)[key]!.stateNode.current);
		}
	}
	return found;
}

/** A prop that is JSX reads as its tag, such as `<Icon>`, instead of React's record of it. */
function shown(value: unknown) {
	if (typeof value !== 'object' || value === null || !('$$typeof' in value)) return value;
	const { type } = value as { type?: unknown };
	if (typeof type === 'string') return `<${type}>`;
	const named = type as { displayName?: string; name?: string } | undefined;
	return `<${registered(type)?.[0] ?? named?.displayName ?? named?.name ?? 'Component'}>`;
}

/** A component's props as its data. `children` is what it draws, which the tree already shows, and a function says nothing. */
function data(props: unknown) {
	if (typeof props !== 'object' || props === null) return undefined;
	const entries = Object.entries(props)
		.filter(([name, value]) => name !== 'children' && typeof value !== 'function')
		.map(([name, value]) => [name, shown(value)] as const);
	return entries.length ? () => Object.fromEntries(entries) : undefined;
}

/**
 * Finds the app's components in React's own tree, so a capture needs no tag for them. A component counts when the
 * Vite plugin registered it, which is how the app's components are told from a library's, and how a name survives a
 * minified build. Its roots are the nearest elements it draws.
 */
export function readComponents(): Map<Element, Component[]> {
	const found = new Map<Element, Component[]>();
	if (!globalThis.__feedbackComponents) return found;

	/** Walks a fiber and its siblings, and returns the nearest elements they draw: in place, and through a portal. */
	const walk = (first: Fiber | null) => {
		const drawn = { own: [] as Element[], portal: [] as Element[] };
		for (let fiber = first; fiber; fiber = fiber.sibling) {
			if (fiber.tag === hoisted) continue;
			if (typeof fiber.type === 'string' && fiber.stateNode instanceof Element) {
				drawn.own.push(fiber.stateNode);
				walk(fiber.child);
				continue;
			}
			const below = walk(fiber.child);
			const entry = composites.has(fiber.tag) ? (registered(fiber.type) ?? registered(fiber.elementType)) : undefined;
			// What a component sends through a portal is a part of it, and its box only when it draws nothing in place.
			const roots = below.own.length ? below.own : below.portal;
			if (entry && roots.length) {
				const component = { tag: { name: entry[0], source: entry[1], data: data(fiber.memoizedProps) }, roots };
				for (const root of roots) found.set(root, [component, ...(found.get(root) ?? [])]);
			}
			if (fiber.tag === portal) {
				drawn.portal.push(...below.own, ...below.portal);
			} else {
				drawn.own.push(...below.own);
				drawn.portal.push(...below.portal);
			}
		}
		return drawn;
	};

	for (const tree of trees()) walk(tree.child);
	return found;
}
