#!/usr/bin/env node
// Plain JavaScript, so `node` and `bun` both run it, from a checkout, from node_modules, or piped in.
import { readFileSync } from 'node:fs';

const usage = `Replays Feedback's tap selection over a JSON export and reports where taps fall through.

Usage: taps.js <feedback.json | -> [--step 8] [--wrapper App]...

A tap "falls through" when it selects the screen, a layer, or a component that is the root of
its screen or layer, such as the screen view's own \`.feedback(self)\`. The report lists the
fall-through share, the bands of the capture where most of a row falls through, and the
elements that sit directly under a root, which are the usual candidates for a missing tag.

React finds every component, so a component that wraps the whole app, such as \`App\`, sits
above each screen's own component. Name it with --wrapper, and the components directly under
it count as roots in its place.

Pass - to read the export from stdin.`;

const args = process.argv.slice(2);
if (args.length === 0 || args.includes('--help')) {
	console.error(usage);
	process.exit(args.length === 0 ? 1 : 0);
}
const option = name => args.flatMap((arg, index) => (arg === name && index + 1 < args.length ? [args[index + 1]] : []));
const step = Number(option('--step')[0] ?? 8);
const wrappers = new Set(option('--wrapper'));

const { nodes } = JSON.parse(readFileSync(args[0] === '-' ? 0 : args[0], 'utf8'));
const byId = new Map(nodes.map(node => [node.id, node]));

const depth = new Map();
for (const node of nodes) depth.set(node.id, node.parent === undefined ? 0 : depth.get(node.parent) + 1);

const contains = ({ frame }, x, y) =>
	frame.x <= x && x <= frame.x + frame.width && frame.y <= y && y <= frame.y + frame.height;
const area = ({ frame }) => frame.width * frame.height;

// Mirrors hitTest in the package: only the topmost layer covering the point competes, then the smallest node wins, and
// the deeper one on a tie.
function hit(x, y) {
	const layer = Math.max(
		0,
		...nodes.filter(node => node.kind === 'layer' && contains(node, x, y)).map(node => node.layer),
	);
	let best;
	for (const node of nodes) {
		if (node.layer !== layer || node.kind === 'screen' || !contains(node, x, y)) continue;
		if (!best || area(node) < area(best) || (area(node) === area(best) && depth.get(node.id) > depth.get(best.id)))
			best = node;
	}
	return best ?? nodes[0];
}

const roots = new Set([0, ...nodes.filter(node => node.kind === 'layer').map(node => node.id)]);
let under = new Set(roots);
while (under.size > 0) {
	const found = nodes.filter(node => node.kind === 'component' && under.has(node.parent) && !roots.has(node.id));
	for (const node of found) roots.add(node.id);
	under = new Set(found.filter(node => wrappers.has(node.name)).map(node => node.id));
}

const title = node => {
	const name = node.label ? `${node.name} "${node.label.slice(0, 50)}"` : node.name;
	return `#${node.id} ${name}${node.source ? ` (${node.source})` : ''}`;
};
const format = value => String(Math.round(value * 1e6) / 1e6);

const { width, height } = nodes[0].frame;
const rows = [];
let total = 0;
let through = 0;
for (let y = step / 2; y < height; y += step) {
	let row = 0;
	let count = 0;
	for (let x = step / 2; x < width; x += step) {
		count++;
		if (roots.has(hit(x, y).id)) row++;
	}
	rows.push([y, row / count]);
	total += count;
	through += row;
}

console.log(
	`Fall-through: ${Math.round((through / total) * 100)}% of ${total} grid points (${format(step)} pt grid over ${format(width)}x${format(height)} pt)`,
);
console.log('Bands where most of a row falls through (often margins and gaps, sometimes a missing tag):');
let band;
for (const [y, share] of [...rows, [height + step, 0]]) {
	if (share > 0.5) band ??= y;
	else if (band !== undefined) {
		console.log(`  y ${Math.round(band - step / 2)}-${Math.round(y - step / 2)}`);
		band = undefined;
	}
}
console.log('Elements directly under a root (each should be fine on its own, or belong to a tagged region):');
for (const node of nodes) {
	if (node.kind === 'element' && roots.has(node.parent) && node.parent !== 0) {
		console.log(`  ${title(node)}  under ${title(byId.get(node.parent))}`);
	}
}
