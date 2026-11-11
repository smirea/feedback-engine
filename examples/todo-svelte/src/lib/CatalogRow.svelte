<script lang="ts">
	import { feedback } from '@smirea/feedback-engine/svelte';

	let { name, detail }: { name: string; detail: string } = $props();

	const initials = $derived(
		name
			.split(' ')
			.slice(0, 2)
			.map(word => word[0])
			.join(''),
	);
</script>

<li class="row" {@attach feedback(undefined, () => ({ name, detail }))}>
	<span class="initials" aria-hidden="true" {@attach feedback('Initials', () => ({ name }))}>{initials}</span>
	<span class="text">
		<strong>{name}</strong>
		<span class="muted">{detail}</span>
	</span>
</li>

<style>
	.row {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		padding: 0.75rem 1rem;
	}

	.initials {
		display: grid;
		place-items: center;
		width: 2.5rem;
		height: 2.5rem;
		border-radius: 0.5rem;
		background: var(--app-border);
		font-size: 0.875rem;
		font-weight: 700;
	}

	.text {
		display: grid;
		gap: 0.125rem;
	}
</style>
