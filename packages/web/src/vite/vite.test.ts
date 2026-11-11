import { expect, test } from 'bun:test';

import { sourceAttribute } from '../dom/tags.ts';
import { addLocations, addReact, componentName, sourceAttribute as pluginAttribute } from './index.js';

test('a component is named after its file, and a route file after its folders', () => {
	expect(componentName('src/lib/ListRow.svelte')).toBe('ListRow');
	expect(componentName('src/lib/todo-row.svelte')).toBe('TodoRow');
	expect(componentName('src/routes/+page.svelte')).toBe('Page');
	expect(componentName('src/routes/lists/[id]/+page.svelte')).toBe('ListsIdPage');
	expect(componentName('src/routes/settings/+layout.svelte')).toBe('SettingsLayout');
});

test('every tag gets its file:line and name, and a bare tag also reports props and state', () => {
	const source = [
		'<script lang="ts">',
		"	import { feedback as tag } from '@smirea/feedback-engine/svelte';",
		'	let { item, onedit, size = 2, class: klass, ...rest }: Props = $props();',
		'	let open = $state(false);',
		'	const total = $derived(item.count * size);',
		'</script>',
		'',
		'<li {@attach tag()}>',
		"	<span {@attach tag('Badge', () => ({ total }))}>{total}</span>",
		'	{#if open}',
		"		<p {@attach tag('Details')}>{item.notes}</p>",
		'	{/if}',
		'	<button {@attach other()}>Edit</button>',
		'</li>',
	].join('\n');
	expect(addLocations(source, 'src/lib/TodoRow.svelte')!.split('\n').slice(7)).toEqual([
		'<li {@attach tag.at("src/lib/TodoRow.svelte:8", "TodoRow", () => ({ item, onedit, size, klass, open }))()}>',
		'	<span {@attach tag.at("src/lib/TodoRow.svelte:9", "TodoRow")(\'Badge\', () => ({ total }))}>{total}</span>',
		'	{#if open}',
		'		<p {@attach tag.at("src/lib/TodoRow.svelte:11", "TodoRow")(\'Details\')}>{item.notes}</p>',
		'	{/if}',
		'	<button {@attach other()}>Edit</button>',
		'</li>',
	]);
});

test('a component that does not import feedback is left alone', () => {
	expect(addLocations('<p {@attach feedback()}>Hi</p>', 'src/lib/Plain.svelte')).toBeUndefined();
	expect(
		addLocations(
			"<script>import { feedback } from 'somewhere-else';</script><p {@attach feedback()}>Hi</p>",
			'src/lib/Other.svelte',
		),
	).toBeUndefined();
});

const reactModule = [
	"import { memo, forwardRef, useState } from 'react';",
	"import { feedback as tag } from '@smirea/feedback-engine/react';",
	'',
	'// café ☕ 🙂',
	"const LIMIT = 'ten';",
	'type Props = { title: string };',
	'',
	'function helper(value: number) {',
	'	return value * 2;',
	'}',
	'',
	'export function Row({ title }: Props) {',
	'	const [open, setOpen] = useState(false);',
	'	return (',
	"		<li ref={tag('Row', () => ({ open }))} onClick={() => setOpen(!open)}>",
	'			<Badge label={title} />',
	"			<span data-feedback-source='kept'>{helper(2)}</span>",
	'			<></>',
	'		</li>',
	'	);',
	'}',
	'',
	'const Badge = memo(({ label }: { label: string }) => <b>{label}</b>);',
	'export const Field = forwardRef<HTMLInputElement, Props>((props, ref) => <input ref={ref} />) as unknown as Fancy;',
	'export default class Board extends Component {}',
].join('\n');

test('a React module registers its components, and its feedback calls and elements get their file:line', () => {
	const lines = addReact(reactModule, 'src/Row.tsx', { elementSources: true })!.split('\n');
	expect(lines.slice(14, 19)).toEqual([
		'		<li data-feedback-source={"src/Row.tsx:15"} ref={tag.at("src/Row.tsx:15")(\'Row\', () => ({ open }))} onClick={() => setOpen(!open)}>',
		'			<Badge label={title} />',
		"			<span data-feedback-source='kept'>{helper(2)}</span>",
		'			<></>',
		'		</li>',
	]);
	expect(lines[22]).toBe(
		'const Badge = memo(({ label }: { label: string }) => <b data-feedback-source={"src/Row.tsx:23"}>{label}</b>);',
	);
	expect(lines.slice(25)).toEqual([
		[
			';(register => {',
			'register(Row, "Row", "src/Row.tsx:12");',
			'register(Badge, "Badge", "src/Row.tsx:23");',
			'register(Field, "Field", "src/Row.tsx:24");',
			'register(Board, "Board", "src/Row.tsx:25");',
			"})((component, name, source) => { if (typeof component === 'function' || (typeof component === 'object' && component !== null)) (globalThis.__feedbackComponents ??= new WeakMap()).set(component, [name, source]); });",
		].join(' '),
		'',
	]);
});

test('without elementSources only the feedback calls change, and every line keeps its number', () => {
	const changed = addReact(reactModule, 'src/Row.tsx')!.split('\n');
	const original = reactModule.split('\n');
	expect(changed.slice(0, 25).filter((line, index) => line !== original[index])).toEqual([
		'		<li ref={tag.at("src/Row.tsx:15")(\'Row\', () => ({ open }))} onClick={() => setOpen(!open)}>',
	]);
});

test('a module with nothing to register is left alone, and so is one that does not parse', () => {
	expect(addReact('export const count = (items: string[]) => items.length;', 'src/count.tsx')).toBeUndefined();
	expect(addReact('export function Broken() { return <div>; }', 'src/Broken.tsx')).toBeUndefined();
});

test('registering never throws on a value that is not a component', () => {
	const registered = addReact("const Label = 'ten';\nconst Sum = add(1, 2);\nfunction Row() {}", 'src/values.jsx')!;
	const run = new Function('add', `${registered}; return Row;`);
	const page = globalThis as { __feedbackComponents?: WeakMap<object, unknown> };
	page.__feedbackComponents = undefined;
	const row = run((a: number, b: number) => a + b);
	expect(page.__feedbackComponents!.get(row)).toEqual(['Row', 'src/values.jsx:3']);
});

test('the plugin and the scene reader agree on the attribute name', () => {
	expect(pluginAttribute).toBe(sourceAttribute);
});
