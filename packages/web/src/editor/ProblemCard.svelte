<svelte:options css="injected" />

<script lang="ts">
	import type { Problem } from '../core/index.ts';

	let { problem }: { problem: Problem } = $props();
</script>

<div class="problem" role="alert">
	<p class="message">{problem.message}</p>
	{#if problem.facts.length}
		<details>
			<summary>Details</summary>
			<pre>{problem.details}</pre>
		</details>
	{/if}
	<button
		type="button"
		onclick={async event => {
			const button = event.currentTarget;
			await navigator.clipboard.writeText(problem.text);
			button.textContent = 'Copied';
			setTimeout(() => (button.textContent = 'Copy Error'), 2000);
		}}>Copy Error</button
	>
</div>

<style>
	.problem {
		display: grid;
		justify-items: start;
		gap: 6px;
		border-radius: 10px;
		padding: 10px 12px;
		background: #2c2c2e;
	}

	.message {
		margin: 0;
		color: #ff453a;
	}

	details {
		width: 100%;
	}

	summary {
		color: #aeaeb2;
		cursor: pointer;
	}

	pre {
		margin: 6px 0 0;
		font-size: 12px;
		white-space: pre-wrap;
		overflow-wrap: anywhere;
		user-select: text;
	}

	button {
		border: 0;
		background: none;
		color: #0a84ff;
		font: inherit;
		cursor: pointer;
	}
</style>
