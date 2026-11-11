<svelte:options css="injected" />

<script lang="ts">
	import { paletteColor, title, type Session } from '../core/index.ts';

	let {
		session,
		version,
		onclose,
		onselect,
		onremove,
	}: {
		session: Session;
		/** Changes whenever the session does, since the session is not reactive by itself. */
		version: number;
		onclose: () => void;
		onselect: (id: number) => void;
		onremove: (id: string) => void;
	} = $props();

	// svelte-ignore state_referenced_locally
	const { capture } = session;
	const items = $derived.by(() => {
		void version;
		return session.items.map((item, index) => ({
			...item,
			number: index + 1,
			color: paletteColor(session.colorIndex(item.target)),
			segments: session.annotations.segments(item.text),
		}));
	});
</script>

<div class="scrim" role="presentation" onclick={event => event.target === event.currentTarget && onclose()}>
	<div class="sheet" role="dialog" tabindex="-1" aria-label="Feedback list">
		<header>
			<h2>Feedback</h2>
			<button type="button" class="done" onclick={onclose}>Done</button>
		</header>
		<div class="scroll">
			{#if !items.length}
				<p class="empty">No feedback yet. Click a component, type, and press the arrow.</p>
			{/if}
			<ul>
				{#each items as item (item.id)}
					<li>
						<button type="button" class="row" onclick={() => onselect(item.target)}>
							<span class="number" style="background:{item.color}">{item.number}</span>
							<span class="text">
								<strong>{title(capture.nodes[item.target]!)}</strong>
								<span>
									{#each item.segments as segment, index (index)}
										{#if segment.reference}<span
												class="token"
												style="background:{paletteColor(session.colorIndex(segment.reference.target))}"
												>{segment.text}</span
											>{:else}{segment.text}{/if}
									{/each}
								</span>
							</span>
						</button>
						<button
							type="button"
							class="remove"
							aria-label="Remove item {item.number}"
							onclick={() => onremove(item.id)}
						>
							<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M10 7V4h4v3M7 7l1 13h8l1-13" /></svg>
						</button>
					</li>
				{/each}
			</ul>
			<h3>Attached context</h3>
			{#each [...capture.environment, ...capture.context] as entry (entry.name)}
				<details>
					<summary>{entry.name}</summary>
					<pre>{entry.value}</pre>
				</details>
			{/each}
		</div>
	</div>
</div>

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
		width: min(100%, 560px);
		max-height: 80%;
		border-radius: 16px 16px 0 0;
		box-sizing: border-box;
		background: #1f1f1f;
	}

	header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 14px 16px 8px;
	}

	h2 {
		margin: 0;
		font-size: 17px;
	}

	h3 {
		margin: 20px 0 6px;
		color: #aeaeb2;
		font-size: 12px;
		font-weight: 600;
		text-transform: uppercase;
	}

	button {
		border: 0;
		background: none;
		color: inherit;
		font: inherit;
		cursor: pointer;
	}

	.done {
		color: #0a84ff;
		font-weight: 600;
	}

	.scroll {
		padding: 0 16px 16px;
		overflow: auto;
	}

	.empty {
		color: #aeaeb2;
	}

	ul {
		margin: 0;
		padding: 0;
		list-style: none;
	}

	li {
		display: flex;
		align-items: flex-start;
		gap: 4px;
		border-bottom: 1px solid rgb(255 255 255 / 0.08);
	}

	.row {
		display: flex;
		flex: 1;
		gap: 10px;
		min-width: 0;
		padding: 10px 0;
		text-align: left;
	}

	.number {
		display: grid;
		flex: none;
		place-items: center;
		width: 22px;
		height: 22px;
		border-radius: 11px;
		font-size: 12px;
		font-weight: 700;
	}

	.text {
		display: grid;
		gap: 2px;
		min-width: 0;
		white-space: pre-wrap;
	}

	.token {
		border-radius: 3px;
		padding: 0 4px;
		font-weight: 600;
	}

	.remove {
		padding: 10px 4px;
		color: #ff453a;
	}

	svg {
		width: 18px;
		height: 18px;
		fill: none;
		stroke: currentColor;
		stroke-width: 2;
		stroke-linecap: round;
		stroke-linejoin: round;
	}

	summary {
		padding: 8px 0;
		cursor: pointer;
	}

	pre {
		margin: 0 0 8px;
		color: #aeaeb2;
		font:
			12px/1.35 ui-monospace,
			'SF Mono',
			Menlo,
			monospace;
		white-space: pre-wrap;
		overflow-wrap: anywhere;
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
