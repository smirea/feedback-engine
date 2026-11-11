<script lang="ts">
	import { feedback } from '@smirea/feedback-engine/svelte';
	import CatalogRow from '../../lib/CatalogRow.svelte';

	const sections = ['Chest', 'Back', 'Legs', 'Shoulders', 'Arms'];
	const movements = ['Bench Press', 'Incline Press', 'Cable Fly', 'Push Up', 'Dip', 'Chest Press'];
	const kinds = ['All', 'Barbell', 'Dumbbell', 'Machine'];
	const featured = Array.from({ length: 12 }, (_, index) => `Plan ${index + 1}`);
	let query = $state('');
	let equipment = $state('All');
	const shown = $derived(movements.filter(movement => movement.toLowerCase().includes(query.toLowerCase())));
</script>

<svelte:head>
	<title>Catalog</title>
</svelte:head>

<main class="screen" {@attach feedback('CatalogScreen', () => ({ query, equipment }))}>
	<h1>Catalog</h1>
	<input class="field" type="search" bind:value={query} aria-label="Search" placeholder="Search" />
	<div class="picker" role="radiogroup" aria-label="Equipment">
		{#each kinds as kind (kind)}
			<button
				type="button"
				class="button"
				role="radio"
				aria-checked={equipment === kind}
				onclick={() => (equipment = kind)}>{kind}</button
			>
		{/each}
	</div>
	<div class="featured" {@attach feedback('Featured')}>
		{#each featured as plan (plan)}
			<span class="plan">{plan}</span>
		{/each}
	</div>
	{#each sections as section (section)}
		<section aria-label={section}>
			<header class="bar">
				<h2>{section}</h2>
				<button type="button" class="more">See {section.length * 7} More</button>
			</header>
			<ul class="card">
				{#each shown as movement (movement)}
					<CatalogRow name={movement} detail="{section} · {equipment === 'All' ? 'Barbell' : equipment}" />
				{/each}
			</ul>
		</section>
	{/each}
</main>

<style>
	.picker {
		display: flex;
		flex-wrap: wrap;
		gap: 0.5rem;
	}

	.featured {
		display: flex;
		gap: 0.5rem;
		overflow-x: auto;
	}

	.plan {
		flex: none;
		width: 7rem;
		border: 1px solid var(--app-border);
		border-radius: 0.5rem;
		padding: 1rem 0.75rem;
	}

	.picker [aria-checked='true'] {
		border-color: var(--app-accent);
		color: var(--app-accent);
	}

	.bar {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
	}

	.more {
		border: 0;
		background: none;
		color: var(--app-muted);
		font: inherit;
		font-size: 0.8125rem;
		text-decoration: underline;
		cursor: pointer;
	}
</style>
