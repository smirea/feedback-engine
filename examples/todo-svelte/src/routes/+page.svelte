<script lang="ts">
	import ListRow from '../lib/ListRow.svelte';
	import { TodoStore } from '../lib/store.svelte';
	import SummaryCard from '../lib/SummaryCard.svelte';

	const store = TodoStore.sample();
	let dialog = $state<HTMLDialogElement>();
	let newListName = $state('');

	function addList(event: SubmitEvent) {
		event.preventDefault();
		const name = newListName.trim();
		if (name) store.addList(name);
		newListName = '';
		dialog?.close();
	}
</script>

<svelte:head>
	<title>Lists</title>
</svelte:head>

<main class="screen">
	<header class="bar">
		<h1>Lists</h1>
		<button type="button" onclick={() => dialog?.showModal()}>New List</button>
	</header>

	<SummaryCard lists={store.lists} />

	<section aria-labelledby="my-lists">
		<h2 id="my-lists">My Lists</h2>
		<ul class="lists">
			{#each store.lists as list (list.id)}
				<ListRow {list} />
			{/each}
		</ul>
	</section>
</main>

<dialog bind:this={dialog} aria-labelledby="new-list">
	<form onsubmit={addList}>
		<h2 id="new-list">New List</h2>
		<input bind:value={newListName} aria-label="Name" placeholder="Name" />
		<div class="actions">
			<button type="button" onclick={() => dialog?.close()}>Cancel</button>
			<button type="submit" class="primary">Add</button>
		</div>
	</form>
</dialog>

<style>
	.screen {
		display: grid;
		gap: 1.5rem;
		width: min(100%, 40rem);
		margin: 0 auto;
		padding: 1.5rem 1rem 3rem;
	}

	.bar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
	}

	h1 {
		margin: 0;
		font-size: 2rem;
		font-weight: 700;
	}

	h2 {
		margin: 0 0 0.5rem;
		color: var(--app-muted);
		font-size: 0.8125rem;
		font-weight: 600;
		text-transform: uppercase;
	}

	.lists {
		margin: 0;
		padding: 0;
		list-style: none;
		border: 1px solid var(--app-border);
		border-radius: 0.75rem;
		background: var(--app-panel);
		color: var(--app-panel-text);
	}

	button {
		border: 1px solid var(--app-border);
		border-radius: 0.375rem;
		padding: 0.5rem 1rem;
		background: transparent;
		color: var(--app-text);
		font-weight: 600;
		cursor: pointer;
	}

	button.primary {
		border-color: var(--app-accent);
		background: var(--app-accent);
		color: var(--app-accent-ink);
	}

	dialog {
		width: min(100% - 2rem, 22rem);
		margin: auto;
		border: 1px solid var(--app-border);
		border-radius: 0.75rem;
		background: var(--app-panel);
		color: var(--app-panel-text);
		padding: 1.25rem;
	}

	dialog::backdrop {
		background: rgb(0 0 0 / 0.5);
	}

	dialog h2 {
		color: inherit;
		font-size: 1.125rem;
		text-transform: none;
	}

	input {
		width: 100%;
		border: 1px solid var(--app-border);
		border-radius: 0.375rem;
		padding: 0.5rem 0.75rem;
		background: var(--app-bg);
		color: var(--app-text);
		font: inherit;
	}

	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
		margin-top: 1rem;
	}
</style>
