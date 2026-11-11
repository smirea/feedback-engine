<script lang="ts">
	import { feedback } from '@smirea/feedback-engine/svelte';
	import { page } from '$app/state';
	import { remaining, store, type TodoItem } from '../../../lib/store.svelte';
	import TodoDetailDialog from '../../../lib/TodoDetailDialog.svelte';
	import TodoRow from '../../../lib/TodoRow.svelte';

	type Filter = 'All' | 'Open' | 'Done';
	const filters: Filter[] = ['All', 'Open', 'Done'];
	const ranks = { high: 0, medium: 1, low: 2, none: 3 };

	const list = $derived(store.list(page.params.id ?? ''));
	let filter = $state<Filter>('All');
	let editing = $state<TodoItem>();
	let newTitle = $state('');

	const visible = $derived.by(() => {
		const items = (list?.items ?? []).filter(item =>
			filter === 'All' ? store.showCompleted || !item.isDone : filter === 'Done' ? item.isDone : !item.isDone,
		);
		if (store.sortOrder === 'due date') return items.toSorted((a, b) => (a.due ?? '9').localeCompare(b.due ?? '9'));
		if (store.sortOrder === 'priority') return items.toSorted((a, b) => ranks[a.priority] - ranks[b.priority]);
		return items;
	});
	const done = $derived(list ? list.items.length - remaining(list) : 0);

	function add(event: SubmitEvent) {
		event.preventDefault();
		if (list && newTitle.trim()) store.add(newTitle.trim(), list.id);
		newTitle = '';
	}
</script>

<svelte:head>
	<title>{list?.name ?? 'List'}</title>
</svelte:head>

{#if list}
	<main class="screen" {@attach feedback('ListDetailScreen', () => ({ listID: list.id, filter, editing }))}>
		<header class="bar">
			<h1>{list.name}</h1>
			<button type="button" class="button" onclick={() => list.items.forEach(item => (item.isDone = true))}
				>Mark All Done</button
			>
		</header>

		<section class="progress card" {@attach feedback('ProgressHeader', () => ({ done, total: list.items.length }))}>
			<strong class="percent">{list.items.length ? Math.round((done / list.items.length) * 100) : 0}%</strong>
			<span>
				<strong>{done} of {list.items.length} done</strong><br />
				<span class="muted">{remaining(list) === 0 ? 'All clear' : `${remaining(list)} to go`}</span>
			</span>
		</section>

		<label class="filter">
			<span class="muted">Filter</span>
			<select class="field" bind:value={filter}>
				{#each filters as name (name)}<option>{name}</option>{/each}
			</select>
		</label>

		<ul class="card">
			{#each visible as item (item.id)}
				<TodoRow {item} ontoggle={() => (item.isDone = !item.isDone)} onedit={() => (editing = item)} />
			{/each}
		</ul>

		<form class="add card" onsubmit={add} {@attach feedback('AddTodoBar', () => ({ title: newTitle }))}>
			<input class="field" bind:value={newTitle} aria-label="New todo" placeholder="New todo" />
			<button type="submit" class="button primary" disabled={!newTitle.trim()}>Add</button>
		</form>
	</main>

	{#if editing}
		{@const item = editing}
		<TodoDetailDialog
			{item}
			onclose={() => (editing = undefined)}
			onsave={changed => {
				store.update(changed, list.id);
				editing = undefined;
			}}
			ondelete={() => {
				store.delete(item.id, list.id);
				editing = undefined;
			}}
		/>
	{/if}
{:else}
	<main class="screen"><h1>No such list</h1></main>
{/if}

<style>
	.progress {
		display: flex;
		align-items: center;
		gap: 1rem;
		padding: 1rem;
	}

	.progress > :global(*) {
		border-top: 0;
	}

	.percent {
		display: grid;
		place-items: center;
		width: 3.5rem;
		height: 3.5rem;
		border: 3px solid var(--app-accent);
		border-radius: 50%;
		font-size: 0.875rem;
	}

	.filter {
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}

	.filter .field {
		width: auto;
	}

	.add {
		display: flex;
		gap: 0.5rem;
		padding: 0.75rem;
	}

	.add > :global(*) {
		border-top: 0;
	}
</style>
