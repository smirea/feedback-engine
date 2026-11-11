<svelte:options css="injected" />

<script lang="ts">
	import Button from './Button.svelte';
	import Editor from './Editor.svelte';
	import type { Engine } from './engine.ts';
	import Pill from './Pill.svelte';

	let { engine }: { engine: Engine } = $props();

	// The engine is not reactive by itself, so it reports each change and this reads it again.
	let version = $state(0);
	// svelte-ignore state_referenced_locally
	engine.onchange = () => (version += 1);
	const shown = $derived.by(() => {
		void version;
		return { pill: engine.pill, remaining: engine.remaining, screen: engine.screen };
	});
</script>

{#if engine.options.button && !shown.screen}
	<Button onpress={() => void engine.present()} />
{/if}
{#if shown.pill}
	<Pill remaining={shown.remaining} onpress={() => void engine.present()} />
{/if}
{#if shown.screen}
	{#key shown.screen}
		<Editor {engine} screen={shown.screen} />
	{/key}
{/if}
