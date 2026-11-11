<svelte:options css="injected" />

<script lang="ts">
	import Editor from './Editor.svelte';
	import type { Engine } from './engine.svelte.ts';
	import Pill from './Pill.svelte';

	let { engine }: { engine: Engine } = $props();
</script>

{#if engine.pill}
	<Pill onpress={() => void engine.present()} />
{/if}
{#if engine.screen}
	{#key engine.screen}
		<Editor {engine} screen={engine.screen} />
	{/key}
{/if}
