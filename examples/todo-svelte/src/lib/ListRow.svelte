<script lang="ts">
	import { remaining, type TodoList } from './store.svelte';

	let { list }: { list: TodoList } = $props();
</script>

<li class="row">
	<span class="dot" data-color={list.color} aria-hidden="true"></span>
	<span class="name">{list.name}</span>
	<span class="count">{remaining(list)}</span>
</li>

<style>
	.row {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		padding: 0.75rem 1rem;
	}

	.row + :global(.row) {
		border-top: 1px solid var(--app-border);
	}

	.dot {
		width: 2rem;
		height: 2rem;
		border-radius: 50%;
		background: var(--app-muted);
	}

	.dot[data-color='blue'] {
		background: #3b82f6;
	}

	.dot[data-color='green'] {
		background: #22c55e;
	}

	.dot[data-color='orange'] {
		background: #f97316;
	}

	.dot[data-color='purple'] {
		background: #a855f7;
	}

	.name {
		flex: 1;
	}

	.count {
		color: var(--app-muted);
	}
</style>
