<script lang="ts">
	import { feedback } from '@smirea/feedback-engine/svelte';
	import { store, type SortOrder } from '../../lib/store.svelte';

	const orders: SortOrder[] = ['manual', 'due date', 'priority'];
</script>

<svelte:head>
	<title>Settings</title>
</svelte:head>

<main
	class="screen"
	{@attach feedback('SettingsScreen', () => ({ showCompleted: store.showCompleted, sortOrder: store.sortOrder }))}
>
	<h1>Settings</h1>

	<section aria-labelledby="display">
		<h2 id="display">Display</h2>
		<div class="card">
			<label class="line"
				>Show completed <input type="checkbox" role="switch" bind:checked={store.showCompleted} /></label
			>
			<label class="line">
				Sort by
				<select class="field" bind:value={store.sortOrder}>
					{#each orders as order (order)}<option value={order}>{order}</option>{/each}
				</select>
			</label>
		</div>
	</section>

	<section aria-labelledby="feedback">
		<h2 id="feedback">Feedback</h2>
		<div class="card">
			<div class="line">
				<button type="button" class="button" onclick={() => globalThis.__feedbackEngine?.countdown()}
					>Send Feedback</button
				>
			</div>
			<p class="line muted">Starts in 5 seconds, so open the screen you mean. With a mouse, Alt+Meta+click anything.</p>
		</div>
	</section>

	<section aria-labelledby="examples">
		<h2 id="examples">Examples</h2>
		<div class="card">
			<a class="line" href="/timeline">Timeline</a>
			<a class="line" href="/catalog">Exercise Catalog</a>
			<a class="line" href="/media">Media</a>
		</div>
	</section>

	<section aria-labelledby="about">
		<h2 id="about">About</h2>
		<div class="card"><p class="line">Version <span class="muted">1.0</span></p></div>
	</section>
</main>

<style>
	.line {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		margin: 0;
		padding: 0.75rem 1rem;
		color: inherit;
		text-decoration: none;
	}

	.line .field {
		width: auto;
		text-transform: capitalize;
	}
</style>
