<script lang="ts">
	import { feedback } from '@stefan.inc/feedback-engine/svelte';
	import Stat from './Stat.svelte';
	import { remaining, type TodoList } from './store.svelte';

	let { lists }: { lists: TodoList[] } = $props();

	const today = new Date().toISOString().slice(0, 10);
	const open = $derived(lists.reduce((sum, list) => sum + remaining(list), 0));
	const dueToday = $derived(
		lists.flatMap(list => list.items).filter(item => !item.isDone && item.due === today).length,
	);
</script>

<section class="summary card" aria-label="Summary" {@attach feedback()}>
	<Stat value={open} label="Open" />
	<Stat value={dueToday} label="Due today" />
	<Stat value={lists.length} label="Lists" />
</section>

<style>
	.summary {
		display: flex;
		gap: 0.75rem;
		padding: 1rem;
	}

	.summary > :global(*) {
		border-top: 0;
	}
</style>
