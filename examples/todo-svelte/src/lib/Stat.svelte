<script lang="ts">
	import { feedback } from '@smirea/feedback-engine/svelte';
	let { value, label }: { value: number; label: string } = $props();
</script>

<div class="stat" {@attach feedback()}>
	<span class="value">{value}</span>
	<span class="label">{label}</span>
</div>

<style>
	.stat {
		display: grid;
		gap: 0.125rem;
		flex: 1;
	}

	.value {
		font-size: 1.75rem;
		font-weight: 700;
		line-height: 1.1;
	}

	.label {
		color: var(--app-muted);
		font-size: 0.8125rem;
	}
</style>
