import type { Annotations } from './annotations.ts';
import { nearestSource, pathFrom, title, type Capture, type Frame } from './model.ts';

const round = (value: number) => Math.round(value * 10) / 10;

const rect = (frame: Frame) => ({
	x: round(frame.x),
	y: round(frame.y),
	width: round(frame.width),
	height: round(frame.height),
});

/** A whole number without decimals, anything else with one. */
export const formatNumber = (value: number) =>
	Number.isFinite(value) ? (Number.isInteger(value) ? String(value) : value.toFixed(1)) : String(value);

/** The JSON export as an object: everything the capture knows except the image. */
export function report(capture: Capture, annotations: Annotations) {
	const pointer = (target: number) => ({
		target,
		title: title(capture.nodes[target]!),
		path: pathFrom(capture, target)
			.map(node => node.id)
			.toReversed(),
		code: nearestSource(capture, target),
	});
	return {
		app: capture.environment.find(entry => entry.name === 'App')?.value ?? 'App',
		captured: capture.date.toISOString().replace(/\.\d+Z$/, 'Z'),
		size: { width: round(capture.size.width), height: round(capture.size.height) },
		visible: rect(capture.visible),
		environment: capture.environment.map(({ name, value }) => ({ name, value })),
		items: annotations.items.map(item => ({
			number: annotations.number(item.target),
			text: item.text,
			...pointer(item.target),
		})),
		references: annotations.used.map(reference => ({
			number: reference.number,
			token: reference.token,
			...pointer(reference.target),
		})),
		context: capture.context.map(({ name, value }) => ({ name, value })),
		nodes: capture.nodes.map(node => ({
			id: node.id,
			parent: node.parent ?? undefined,
			layer: node.layer,
			kind: node.kind,
			name: node.name,
			label: node.label,
			frame: rect(node.frame),
			source: node.source,
			data: node.data,
		})),
	};
}

function sorted(value: unknown): unknown {
	if (Array.isArray(value)) return value.map(sorted);
	if (value && typeof value === 'object') {
		return Object.fromEntries(
			Object.entries(value)
				.filter(([, entry]) => entry !== undefined)
				.toSorted(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
				.map(([key, entry]) => [key, sorted(entry)]),
		);
	}
	return value;
}

/** One object with sorted keys. Keys without a value are left out. */
export function reportJSON(capture: Capture, annotations: Annotations, pretty = true) {
	return JSON.stringify(sorted(report(capture, annotations)), null, pretty ? 2 : undefined);
}
