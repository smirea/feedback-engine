<script lang="ts">
	import Stat from './Stat.svelte';
	import { remaining, type TodoList } from './store.svelte';

	let { lists }: { lists: TodoList[] } = $props();

	const open = $derived(lists.reduce((sum, list) => sum + remaining(list), 0));
	const today = $derived(
		lists
			.flatMap(list => list.items)
			.filter(item => !item.isDone && item.due?.toDateString() === new Date().toDateString()).length,
	);
</script>

<section class="card" aria-label="Summary">
	<Stat value={open} label="Open" />
	<Stat value={today} label="Due today" />
	<Stat value={lists.length} label="Lists" />
</section>

<style>
	.card {
		display: flex;
		gap: 0.75rem;
		border: 1px solid var(--app-border);
		border-radius: 0.75rem;
		background: var(--app-panel);
		color: var(--app-panel-text);
		padding: 1rem;
	}
</style>
