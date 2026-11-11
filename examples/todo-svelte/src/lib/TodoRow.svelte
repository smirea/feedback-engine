<script lang="ts">
	import { feedback } from '@smirea/feedback-engine/svelte';
	import type { TodoItem } from './store.svelte';

	let { item, ontoggle, onedit }: { item: TodoItem; ontoggle: () => void; onedit: () => void } = $props();
</script>

<li class="todo" {@attach feedback(undefined, () => ({ item }))}>
	<button
		type="button"
		class="check"
		class:done={item.isDone}
		aria-label={item.isDone ? 'Mark not done' : 'Mark done'}
		onclick={ontoggle}
	></button>
	<button type="button" class="body" onclick={onedit}>
		<span class="title" class:done={item.isDone}>{item.title}</span>
		{#if item.notes}<span class="muted">{item.notes}</span>{/if}
	</button>
	{#if item.due}<span class="muted">{item.due.slice(5)}</span>{/if}
	{#if item.priority !== 'none'}<span
			class="flag"
			data-priority={item.priority}
			role="img"
			aria-label="{item.priority} priority"
		></span>{/if}
</li>

<style>
	.todo {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		padding: 0.625rem 1rem;
	}

	.check {
		flex: none;
		width: 1.5rem;
		height: 1.5rem;
		border: 2px solid var(--app-muted);
		border-radius: 50%;
		background: none;
		cursor: pointer;
	}

	.check.done {
		border-color: var(--app-accent);
		background: var(--app-accent);
	}

	.body {
		display: grid;
		flex: 1;
		gap: 0.125rem;
		border: 0;
		padding: 0;
		background: none;
		color: inherit;
		text-align: left;
		cursor: pointer;
	}

	.title.done {
		color: var(--app-muted);
		text-decoration: line-through;
	}

	.flag {
		width: 0.625rem;
		height: 0.625rem;
		border-radius: 50%;
		background: #3b82f6;
	}

	.flag[data-priority='medium'] {
		background: #f97316;
	}

	.flag[data-priority='high'] {
		background: #ef4444;
	}
</style>
