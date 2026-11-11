<script lang="ts">
	import { feedback } from '@smirea/feedback-engine/svelte';

	const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
	const sessions = [
		'Warm-up',
		'Squat',
		'Bench press',
		'Row',
		'Overhead press',
		'Deadlift',
		'Pull-up',
		'Core',
		'Stretch',
	];
</script>

<svelte:head>
	<title>Timeline</title>
</svelte:head>

<main class="screen" {@attach feedback('TimelineScreen')}>
	<h1>Timeline</h1>
	{#each days as day (day)}
		<section class="day card">
			<header class="pinned" {@attach feedback('DayHeader', () => ({ day, count: sessions.length }))}>
				<strong>{day}</strong>
				<span class="muted">{sessions.length} sessions</span>
			</header>
			{#each sessions as session, index (session)}
				<div
					class="session"
					{@attach feedback('TimelineRow', () => ({ title: `${day} ${session}`, minutes: 20 + index * 5 }))}
				>
					<strong>{day} {session}</strong>
					<span class="muted">{20 + index * 5} min</span>
				</div>
			{/each}
		</section>
	{/each}
</main>

<style>
	.pinned {
		position: sticky;
		top: 0;
		display: flex;
		justify-content: space-between;
		border-radius: 0.75rem 0.75rem 0 0;
		padding: 0.75rem 1rem;
		background: var(--app-panel);
	}

	.session {
		display: grid;
		gap: 0.125rem;
		padding: 0.75rem 1rem;
	}
</style>
