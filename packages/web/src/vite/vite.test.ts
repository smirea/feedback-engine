import { expect, test } from 'bun:test';
import { addLocations, componentName } from './index.js';

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
