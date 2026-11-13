import { expect, test } from 'bun:test';
import {
	Annotations,
	buildTree,
	describe,
	hitTest,
	place,
	reportJSON,
	Session,
	tag,
	title,
	type Capture,
	type RawScene,
} from './index.ts';

const frame = (x: number, y: number, width: number, height: number) => ({ x, y, width, height });
const size = { width: 400, height: 800 };
const screenLayer = { name: 'Screen', frame: frame(0, 0, 400, 800) };

function captureOf(scene: RawScene): Capture {
	return {
		date: new Date('2026-05-01T12:00:00.250Z'),
		size: scene.size,
		visible: frame(0, 0, 400, 800),
		nodes: buildTree(scene),
		environment: [{ name: 'App', value: 'Demo' }],
		context: [{ name: 'Store', value: 'Store(count: 2)' }],
	};
}

const outline = (capture: Capture) =>
	capture.nodes.map(
		node => `${node.id} ${node.parent ?? '-'} L${node.layer} ${title(node)} @${node.frame.x},${node.frame.y}`,
	);

const rowScene = (): RawScene => ({
	size,
	layers: [screenLayer],
	nodes: [
		{
			parent: null,
			layer: 0,
			kind: 'component',
			name: 'Row',
			frame: frame(0, 200, 400, 60),
			source: 'src/Row.svelte:200',
		},
		{ parent: 0, layer: 0, kind: 'element', name: 'Text', label: 'Milk', frame: frame(16, 210, 200, 40) },
		{ parent: 0, layer: 0, kind: 'element', name: 'Button', label: 'Delete', frame: frame(340, 210, 40, 40) },
	],
});

test('nodes are numbered depth-first in reading order whatever order the page listed them in', () => {
	const scene: RawScene = {
		size,
		layers: [screenLayer],
		nodes: [
			{ parent: null, layer: 0, kind: 'component', name: 'Footer', frame: frame(0, 700, 400, 44), source: 'a:1' },
			{ parent: null, layer: 0, kind: 'component', name: 'List', frame: frame(0, 100, 400, 500), source: 'a:2' },
			{ parent: 1, layer: 0, kind: 'element', name: 'Button', label: 'Info', frame: frame(360, 110, 24, 24) },
			{ parent: 1, layer: 0, kind: 'element', name: 'Button', label: 'Done', frame: frame(10, 110, 24, 24) },
			{ parent: 0, layer: 0, kind: 'element', name: 'Text', label: '3 items', frame: frame(16, 710, 100, 24) },
		],
	};
	expect(outline(captureOf(scene))).toEqual([
		'0 - L0 Screen @0,0',
		'1 0 L0 List @0,100',
		'2 1 L0 Button "Done" @10,110',
		'3 1 L0 Button "Info" @360,110',
		'4 0 L0 Footer @0,700',
		'5 4 L0 Text "3 items" @16,710',
	]);
});

test('a dialog leaves out only what it completely covers, and taps on it stay inside it', () => {
	const scene: RawScene = {
		size,
		layers: [screenLayer, { name: 'Dialog', frame: frame(0, 400, 400, 400) }],
		nodes: [
			{ parent: null, layer: 0, kind: 'component', name: 'ListScreen', frame: frame(0, 0, 400, 800), source: 'a:1' },
			{ parent: 0, layer: 0, kind: 'element', name: 'Button', label: 'Top', frame: frame(10, 100, 100, 40) },
			{ parent: 0, layer: 0, kind: 'element', name: 'Button', label: 'Half', frame: frame(10, 380, 100, 40) },
			{ parent: 0, layer: 0, kind: 'element', name: 'Button', label: 'Hidden', frame: frame(10, 500, 100, 40) },
			{ parent: null, layer: 1, kind: 'component', name: 'EditDialog', frame: frame(0, 400, 400, 400), source: 'a:9' },
			{ parent: 4, layer: 1, kind: 'element', name: 'Button', label: 'Save', frame: frame(300, 410, 80, 36) },
		],
	};
	const result = captureOf(scene);
	expect(outline(result)).toEqual([
		'0 - L0 Screen @0,0',
		'1 0 L0 ListScreen @0,0',
		'2 1 L0 Button "Top" @10,100',
		'3 1 L0 Button "Half" @10,380',
		'4 0 L1 Dialog @0,400',
		'5 4 L1 EditDialog @0,400',
		'6 5 L1 Button "Save" @300,410',
	]);
	expect(title(result.nodes[hitTest(result, { x: 50, y: 410 })]!)).toBe('EditDialog');
	expect(title(result.nodes[hitTest(result, { x: 50, y: 390 })]!)).toBe('Button "Half"');
});

test('children of a node that is left out move to the nearest node that stays, and frames are clipped', () => {
	const scene: RawScene = {
		size,
		layers: [screenLayer],
		nodes: [
			{ parent: null, layer: 0, kind: 'component', name: 'Page', frame: frame(0, 0, 400, 2000), source: 'a:1' },
			{ parent: 0, layer: 0, kind: 'component', name: 'Collapsed', frame: frame(0, 100, 0, 0), source: 'a:2' },
			{ parent: 1, layer: 0, kind: 'element', name: 'Text', label: 'Kept', frame: frame(-20, 100, 100, 20) },
			{ parent: 0, layer: 0, kind: 'element', name: 'Text', label: 'Below', frame: frame(0, 900, 100, 20) },
			{ parent: 0, layer: 0, kind: 'element', name: 'Text', label: 'Broken', frame: frame(0, Number.NaN, 100, 20) },
		],
	};
	const result = captureOf(scene);
	expect(outline(result)).toEqual(['0 - L0 Screen @0,0', '1 0 L0 Page @0,0', '2 1 L0 Text "Kept" @0,100']);
	expect(result.nodes[1]!.frame).toEqual(frame(0, 0, 400, 800));
	expect(result.nodes[2]!.frame).toEqual(frame(0, 100, 80, 20));
});

test('the JSON export holds the items and the whole tree with sorted keys', () => {
	const scene: RawScene = {
		size,
		layers: [screenLayer],
		nodes: [
			{
				parent: null,
				layer: 0,
				kind: 'component',
				name: 'ListScreen',
				frame: frame(0, 100, 400, 600),
				source: 'src/ListScreen.svelte:100',
				data: 'filter: open',
			},
			{
				parent: 0,
				layer: 0,
				kind: 'element',
				name: 'Button',
				label: 'Mark done',
				frame: frame(20, 210.25, 24, 24),
				source: 'src/ListScreen.svelte:104',
			},
		],
	};
	const result = captureOf(scene);
	const annotations = new Annotations();
	annotations.submit('Make it bigger', hitTest(result, { x: 30, y: 220 }));
	const json = reportJSON(result, annotations);
	expect(JSON.parse(json)).toEqual({
		app: 'Demo',
		captured: '2026-05-01T12:00:00Z',
		size: { width: 400, height: 800 },
		visible: { x: 0, y: 0, width: 400, height: 800 },
		environment: [{ name: 'App', value: 'Demo' }],
		items: [
			{
				number: 1,
				text: 'Make it bigger',
				target: 2,
				title: 'Button "Mark done"',
				path: [0, 1, 2],
				code: 'src/ListScreen.svelte:104',
			},
		],
		references: [],
		context: [{ name: 'Store', value: 'Store(count: 2)' }],
		nodes: [
			{ id: 0, layer: 0, kind: 'screen', name: 'Screen', frame: { x: 0, y: 0, width: 400, height: 800 } },
			{
				id: 1,
				parent: 0,
				layer: 0,
				kind: 'component',
				name: 'ListScreen',
				frame: { x: 0, y: 100, width: 400, height: 600 },
				source: 'src/ListScreen.svelte:100',
				data: 'filter: open',
			},
			{
				id: 2,
				parent: 1,
				layer: 0,
				kind: 'element',
				name: 'Button',
				label: 'Mark done',
				frame: { x: 20, y: 210.3, width: 24, height: 24 },
				source: 'src/ListScreen.svelte:104',
			},
		],
	});
	expect(json.slice(0, 40)).toBe('{\n  "app": "Demo",\n  "captured": "2026-0');
	expect(Object.keys(JSON.parse(json))).toEqual([
		'app',
		'captured',
		'context',
		'environment',
		'items',
		'nodes',
		'references',
		'size',
		'visible',
	]);
});

test('unshared items are the ones no completed share included', () => {
	const session = new Session(captureOf(rowScene()));
	for (const [x, text] of [
		[50, 'Bigger title'],
		[350, 'Wrong color'],
	] as const) {
		session.pick({ x, y: 220 });
		session.text = text;
		session.submit();
	}
	expect(session.unshared.map(item => item.text)).toEqual(['Bigger title', 'Wrong color']);
	session.markShared(session.items);
	session.remove(session.items[1]!.id);
	session.pick({ x: 350, y: 220 });
	session.text = 'Typo';
	session.submit();
	session.pick({ x: 50, y: 220 });
	session.text = 'Huge title';
	session.submit();
	expect(session.unshared.map(item => item.text)).toEqual(['Typo']);
	expect(session.items.map(item => item.text)).toEqual(['Huge title', 'Typo']);
});

test("tapping an item's box edits its feedback, and other levels keep their own", () => {
	const session = new Session(captureOf(rowScene()));
	const milk = { x: 50, y: 220 };
	session.pick(milk);
	session.step(1);
	session.text = 'Row is too tall';
	session.submit();

	session.text = 'Note on the whole screen';
	session.pick(milk);
	expect(title(session.target)).toBe('Row');
	expect(session.text).toBe('Row is too tall');
	session.text = 'Row is too tall and grey';
	expect(session.isTyping).toBe(true);

	session.step(0);
	expect(title(session.target)).toBe('Text "Milk"');
	expect(session.editing).toBeUndefined();
	expect(session.text).toBe('Note on the whole screen');

	session.step(1);
	expect(session.text).toBe('Row is too tall');
	expect(session.canSubmit).toBe(false);

	session.pick(milk);
	expect(title(session.target)).toBe('Text "Milk"');
	session.pick({ x: 350, y: 220 });
	expect(title(session.target)).toBe('Row');
	session.text = 'Row is too short';
	session.pick(milk);
	expect(title(session.target)).toBe('Row');
	expect(session.text).toBe('Row is too short');
	session.submit();
	expect(session.items.map(item => item.text)).toEqual(['Row is too short']);
	expect(session.text).toBe('Note on the whole screen');
});

test('typing @ picks a node to reference without moving the target', () => {
	const session = new Session(captureOf(rowScene()));
	const remove = { x: 350, y: 220 };
	session.pick({ x: 50, y: 220 });
	session.text = 'Too close to @';
	expect(session.isReferencing).toBe(true);
	expect(session.referenceTarget).toBeUndefined();

	session.pick(remove);
	expect(title(session.target)).toBe('Text "Milk"');
	expect(title(session.referenceTarget!)).toBe('Button "Delete"');
	session.stepReference(1);
	expect(title(session.referenceTarget!)).toBe('Row');
	session.stepReference(0);
	session.insertReference();
	expect(session.text).toBe('Too close to @1_Button ');
	expect(session.isReferencing).toBe(false);

	session.text += 'and @';
	session.pick({ x: 100, y: 255 });
	session.insertReference();
	session.text += 'below @';
	session.pick(remove);
	session.insertReference();
	expect(session.text).toBe('Too close to @1_Button and @2_Row below @1_Button ');
	session.text += 'x';
	session.pick(remove);
	expect(title(session.target)).toBe('Button "Delete"');

	session.pick({ x: 50, y: 220 });
	session.text = 'email@';
	expect(session.isReferencing).toBe(false);
});

test('references share numbers and colors with items in the order their nodes were first used', () => {
	const session = new Session(captureOf(rowScene()));
	session.pick({ x: 50, y: 220 });
	session.text = 'Align with @';
	session.pick({ x: 350, y: 220 });
	session.insertReference();
	session.submit();
	session.pick({ x: 350, y: 220 });
	session.text = 'Smaller';
	session.submit();
	const [milk, remove] = session.items.map(item => item.target);
	expect([session.colorIndex(milk!), session.colorIndex(remove!)]).toEqual([1, 0]);
	expect(
		session.annotations
			.segments(session.items[0]!.text)
			.map(segment => [segment.text, segment.reference ? tag(segment.reference) : '']),
	).toEqual([
		['Align with ', ''],
		['@1_Button', '@1'],
	]);
	expect(JSON.parse(session.json).references).toEqual([
		{ number: 1, token: '@1_Button', target: 3, title: 'Button "Delete"', path: [0, 1, 3], code: 'src/Row.svelte:200' },
	]);
	expect(JSON.parse(session.json).items.map((item: { number: number }) => item.number)).toEqual([2, 1]);

	session.remove(session.items[1]!.id);
	session.pick({ x: 50, y: 300 });
	session.text = 'Too empty';
	session.submit();
	expect(JSON.parse(session.json).items.map((item: { number: number }) => item.number)).toEqual([2, 3]);
});

class Entry {
	kg = 72.57477920000001;
	note: string | null = null;
	onTap = () => {};
}

class Counter {
	#count = 2;
	get count() {
		return this.#count;
	}
	increment() {
		this.#count += 1;
	}
}

test('a plain object at the top level reads as one line per property', () => {
	expect(describe({ title: 'Milk', isDone: true, due: undefined, onTap: () => {} })).toBe(
		'title: Milk\nisDone: true\ndue: undefined',
	);
	expect(describe('Milk')).toBe('Milk');
	expect(describe({})).toBeUndefined();
	expect(describe(() => {})).toBeUndefined();
});

test('nested values read like code and leave out functions', () => {
	expect(
		describe({
			entry: new Entry(),
			tags: ['a', 'b'],
			size: { width: 0.12345, height: 60 },
			seen: new Map([['milk', 1]]),
			when: new Date('2026-05-01T12:00:00Z'),
			store: new Counter(),
			tiny: 1.23e-16,
			weight: { toFeedback: () => 181.6 },
		}),
	).toBe(
		[
			'entry: Entry(kg: 72.575, note: null)',
			'tags: ["a", "b"]',
			'size: {width: 0.123, height: 60}',
			'seen: ["milk": 1]',
			'when: 2026-05-01T12:00:00.000Z',
			'store: Counter(count: 2)',
			'tiny: 1.23e-16',
			'weight: 181.6',
		].join('\n'),
	);
});

test('nesting stops after 3 levels, lists after 10 elements, and the whole description at 1,500 characters', () => {
	const deep = { a: { b: { c: { d: { e: 1 } } }, list: [[['x']]] } };
	expect(describe(deep)).toBe('a: {b: {c: {d: {…}}}, list: [[[…]]]}');
	expect(describe(deep, 8000)).toBe('a: {b: {c: {d: {e: 1}}}, list: [[["x"]]]}');
	expect(describe({ n: Array.from({ length: 12 }, (_, index) => index) })).toBe(
		'n: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, … 2 more]',
	);
	const long = describe({ text: 'x'.repeat(2000) })!;
	expect(long.length).toBe(1500 + '… (truncated)'.length);
	expect(long.endsWith('x… (truncated)')).toBe(true);
});

test('a tall capture is cut half a screen below the lowest box or card, and is at least one screen tall', () => {
	const tall = { width: 400, height: 5000 };
	const near = place([frame(0, 100, 60, 44)], [60], tall, 150, 800);
	expect(near.shot).toEqual(frame(340, 24, 400, 800));
	expect(near.size.height).toBe(848);
	expect(place([frame(0, 3000, 60, 50)], [60], tall, 150, 800).shot.height).toBe(3055 + 400);
	expect(place([frame(0, 100, 60, 44)], [60], tall, 150, 800, [frame(0, 4000, 60, 50)]).shot.height).toBe(4050 + 400);
});
