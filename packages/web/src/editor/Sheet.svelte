<svelte:options css="injected" />

<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		label,
		onsubmit,
		header,
		children,
	}: { label: string; onsubmit: () => void; header: Snippet; children: Snippet } = $props();
</script>

<div class="scrim" role="presentation">
	<form
		class="sheet"
		aria-label={label}
		novalidate
		onsubmit={event => {
			event.preventDefault();
			onsubmit();
		}}
	>
		<header>{@render header()}</header>
		<div class="scroll">{@render children()}</div>
	</form>
</div>

<!-- The shared styles reach into content another component scopes, and `:where` keeps them below that component's own. -->
<style>
	.scrim {
		position: absolute;
		inset: 0;
		z-index: 5;
		display: grid;
		place-items: end center;
		background: rgb(0 0 0 / 0.5);
	}

	.sheet {
		display: flex;
		flex-direction: column;
		width: min(100%, 480px);
		max-height: 85%;
		border-radius: 16px 16px 0 0;
		box-sizing: border-box;
		background: #1f1f1f;
	}

	header {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 14px 16px 8px;
	}

	header :global(h2) {
		flex: 1;
		margin: 0;
		font-size: 16px;
		text-align: center;
	}

	.scroll {
		display: grid;
		gap: 8px;
		padding: 8px 16px 16px;
		overflow: auto;
	}

	:where(.sheet) :global(:is(button, input)) {
		color: inherit;
		font: inherit;
	}

	:where(.sheet) :global(button) {
		border: 0;
		background: none;
		cursor: pointer;
	}

	:where(.sheet) :global(button:disabled) {
		cursor: default;
		opacity: 0.5;
	}

	:where(.sheet) :global(.link) {
		color: #0a84ff;
	}

	:where(.sheet) :global(.caption) {
		color: #aeaeb2;
		font-size: 12px;
		font-weight: 600;
		text-transform: uppercase;
	}

	:where(.sheet) :global(label:has(> .caption)) {
		display: grid;
		gap: 6px;
		margin-bottom: 8px;
	}

	:where(.sheet) :global(:is(input:not([type]), input[type='url'])) {
		border: 0;
		border-radius: 10px;
		padding: 10px 12px;
		background: #2e2e30;
	}

	@media (min-width: 900px) {
		.scrim {
			place-items: center;
		}

		.sheet {
			border-radius: 16px;
		}
	}
</style>
