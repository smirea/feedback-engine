<script lang="ts">
	import { feedback } from '@stefan.inc/feedback-engine/svelte';
	import type { Priority, TodoItem } from './store.svelte';

	let {
		item,
		onsave,
		ondelete,
		onclose,
	}: { item: TodoItem; onsave: (item: TodoItem) => void; ondelete: () => void; onclose: () => void } = $props();

	// svelte-ignore state_referenced_locally
	let draft = $state({ ...item });
	const priorities: Priority[] = ['none', 'low', 'medium', 'high'];
</script>

<dialog
	class="sheet"
	aria-labelledby="details"
	{onclose}
	{@attach node => {
		node.showModal();
	}}
	{@attach feedback(undefined, () => ({ item: draft }))}
>
	<form
		onsubmit={event => {
			event.preventDefault();
			onsave(draft);
		}}
	>
		<h2 id="details">Details</h2>
		<input class="field" bind:value={draft.title} aria-label="Title" placeholder="Title" />
		<textarea class="field" bind:value={draft.notes} aria-label="Notes" placeholder="Notes" rows="3"></textarea>
		<label class="line">
			Due date
			<input
				type="checkbox"
				checked={draft.due !== undefined}
				onchange={event =>
					(draft.due = event.currentTarget.checked ? new Date().toISOString().slice(0, 10) : undefined)}
			/>
		</label>
		{#if draft.due !== undefined}
			<label class="line">Due <input class="field date" type="date" bind:value={draft.due} /></label>
		{/if}
		<label class="line">
			Priority
			<select class="field select" bind:value={draft.priority}>
				{#each priorities as priority (priority)}<option value={priority}>{priority}</option>{/each}
			</select>
		</label>
		<button type="button" class="button danger" onclick={ondelete}>Delete Todo</button>
		<div class="actions">
			<button type="button" class="button" onclick={onclose}>Cancel</button>
			<button type="submit" class="button primary">Save</button>
		</div>
	</form>
</dialog>

<style>
	.line {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
	}

	.date,
	.select {
		width: auto;
		text-transform: capitalize;
	}
</style>
