<script lang="ts">
	import { feedback } from '@smirea/feedback-engine/svelte';
	import ListRow from '../lib/ListRow.svelte';
	import { store } from '../lib/store.svelte';
	import SummaryCard from '../lib/SummaryCard.svelte';

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

<main class="screen" {@attach feedback('ListsScreen', () => ({ isAddingList: dialog?.open ?? false, newListName }))}>
	<header class="bar">
		<h1>Lists</h1>
		<button type="button" class="button" onclick={() => dialog?.showModal()}>New List</button>
	</header>

	<SummaryCard lists={store.lists} />

	<section aria-labelledby="my-lists">
		<h2 id="my-lists">My Lists</h2>
		<ul class="card">
			{#each store.lists as list (list.id)}
				<li><a href="/lists/{list.id}"><ListRow {list} /></a></li>
			{/each}
		</ul>
	</section>
</main>

<dialog class="sheet" bind:this={dialog} aria-labelledby="new-list">
	<form onsubmit={addList}>
		<h2 id="new-list">New List</h2>
		<input class="field" bind:value={newListName} aria-label="Name" placeholder="Name" />
		<div class="actions">
			<button type="button" class="button" onclick={() => dialog?.close()}>Cancel</button>
			<button type="submit" class="button primary">Add</button>
		</div>
	</form>
</dialog>

<style>
	a {
		display: block;
		color: inherit;
		text-decoration: none;
	}
</style>
