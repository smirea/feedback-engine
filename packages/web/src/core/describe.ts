export const dataLimit = 1500;
export const contextLimit = 8000;
const maxElements = 10;

type Depth = { level: number; max: number };
const next = (depth: Depth) => ({ level: depth.level + 1, max: depth.max });

/** A value that Feedback describes as `toFeedback()` in its place, at any depth. */
export type FeedbackRepresentable = { toFeedback(): unknown };

const truncate = (text: string, limit: number) => (text.length > limit ? `${text.slice(0, limit)}… (truncated)` : text);

/**
 * Describes a value the way it reads in code. A plain object at the top level is one `label: value` line per
 * property. A larger `limit` is for app-wide context, which gets the room to nest deeper.
 */
export function describe(value: unknown, limit = dataLimit): string | undefined {
	const depth = { level: 0, max: limit > dataLimit ? 6 : 3 };
	const unwrapped = unwrap(value);
	if (isPlain(unwrapped)) {
		const lines = fields(unwrapped, depth).map(([label, text]) => `${label}: ${text}`);
		return lines.length ? truncate(lines.join('\n'), limit) : undefined;
	}
	const text = render(unwrapped, depth);
	return text === undefined ? undefined : truncate(text, limit);
}

function unwrap(value: unknown): unknown {
	return typeof (value as FeedbackRepresentable | null)?.toFeedback === 'function'
		? (value as FeedbackRepresentable).toFeedback()
		: value;
}

function isPlain(value: unknown): value is Record<string, unknown> {
	if (value === null || typeof value !== 'object') return false;
	const prototype = Object.getPrototypeOf(value);
	return prototype === Object.prototype || prototype === null;
}

/** `undefined` hides the value: it is a function, a DOM node, or an object made only of those. Strings are quoted below the top level so they stand apart from the punctuation around them. */
function render(input: unknown, depth: Depth): string | undefined {
	const value = unwrap(input);
	if (value === null) return 'null';
	switch (typeof value) {
		case 'undefined':
			return 'undefined';
		case 'string':
			return depth.level > 0 ? JSON.stringify(value) : value;
		case 'number':
			return number(value);
		case 'bigint':
			return `${value}n`;
		case 'boolean':
			return String(value);
		case 'function':
		case 'symbol':
			return undefined;
	}
	const object = value as object;
	if (isOpaque(object)) return undefined;
	if (object instanceof Date) return Number.isNaN(object.getTime()) ? 'Invalid Date' : object.toISOString();
	if (object instanceof Error) return `${object.name}(${JSON.stringify(object.message)})`;
	const deep = depth.level >= depth.max;
	if (Array.isArray(object) || object instanceof Set) {
		const values = [...object];
		if (deep && values.length) return '[…]';
		return `[${limited(values.map(entry => render(entry, next(depth))).filter(text => text !== undefined))}]`;
	}
	if (object instanceof Map) {
		if (deep && object.size) return '[…]';
		const pairs = [...object].map(
			([key, entry]) => `${render(key, next(depth)) ?? '…'}: ${render(entry, next(depth)) ?? '…'}`,
		);
		return pairs.length ? `[${limited(pairs)}]` : '[:]';
	}
	const name = isPlain(object) ? '' : (object.constructor?.name ?? '');
	const [open, close] = name ? [`${name}(`, ')'] : ['{', '}'];
	const keys = fieldNames(object);
	if (deep && keys.length) return `${open}…${close}`;
	const parts = fields(object, next(depth));
	if (!parts.length && keys.length) return undefined;
	return `${open}${parts.map(([label, text]) => `${label}: ${text}`).join(', ')}${close}`;
}

function fields(object: object, depth: Depth): [string, string][] {
	const parts: [string, string][] = [];
	for (const key of fieldNames(object)) {
		let value: unknown;
		try {
			value = (object as Record<string, unknown>)[key];
		} catch {
			continue;
		}
		const text = render(value, depth);
		if (text !== undefined) parts.push([key, text]);
	}
	return parts;
}

/** Own properties, then getters from the class. Svelte compiles a class's `$state` fields into getters on the prototype, so they would otherwise read as empty. */
function fieldNames(object: object): string[] {
	const names = Object.keys(object);
	for (
		let prototype = Object.getPrototypeOf(object);
		prototype && prototype !== Object.prototype;
		prototype = Object.getPrototypeOf(prototype)
	) {
		for (const [key, descriptor] of Object.entries(Object.getOwnPropertyDescriptors(prototype))) {
			if (descriptor.get && !names.includes(key)) names.push(key);
		}
	}
	return names;
}

function isOpaque(object: object) {
	return (
		(typeof Node !== 'undefined' && object instanceof Node) ||
		(typeof Window !== 'undefined' && object instanceof Window) ||
		object instanceof Promise ||
		object instanceof WeakMap ||
		object instanceof WeakSet
	);
}

function limited(parts: string[]) {
	return parts.length > maxElements
		? [...parts.slice(0, maxElements), `… ${parts.length - maxElements} more`].join(', ')
		: parts.join(', ');
}

/** Binary floating point turns 72.575 into 72.57477920000001, so floats keep 3 decimals, or 3 significant digits below 1, and switch to exponent notation where that would take more than 15 decimals. */
function number(value: number) {
	if (!Number.isFinite(value) || Number.isInteger(value)) return String(value);
	const magnitude = Math.abs(value);
	const decimals = magnitude >= 1 ? 3 : 2 - Math.floor(Math.log10(magnitude));
	if (decimals > 15)
		return value
			.toExponential(2)
			.replace(/\.?0+e/, 'e')
			.replace('e+', 'e');
	const text = value.toFixed(decimals).replace(/\.?0+$/, '');
	return text === '-0' ? '0' : text;
}
