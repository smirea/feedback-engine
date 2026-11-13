<svelte:options css="injected" />

<script lang="ts">
	import { Problem, taskTitle, type Fact, type FeedbackItem, type Session, type Toast } from '../core/index.ts';
	import type { Screen } from '../dom/capture.ts';
	import { buildExport } from '../dom/share.ts';
	import { postId, postWebhook, type Webhook } from '../dom/webhook.ts';
	import ProblemCard from './ProblemCard.svelte';

	let {
		screen,
		session,
		webhook,
		onclose,
		onposted,
	}: {
		screen: Screen;
		session: Session;
		webhook: Webhook;
		onclose: () => void;
		onposted: (items: FeedbackItem[], toast: Toast) => void;
	} = $props();

	// The editor makes a new sheet for each post, so the first values are the only ones.
	// svelte-ignore state_referenced_locally
	const items = [...session.items];
	// svelte-ignore state_referenced_locally
	const title = taskTitle(session.capture, items).placeholder;
	// svelte-ignore state_referenced_locally
	const report = session.compactJSON;
	const id = postId();
	let step = $state('Drawing the image');
	let problem = $state<Problem>();

	async function post() {
		problem = undefined;
		step = 'Drawing the image';
		const started = performance.now();
		const facts: Fact[] = [
			{ label: 'Post', value: id },
			{ label: 'Report', value: `${new TextEncoder().encode(report).length} bytes` },
		];
		try {
			const { image } = await buildExport(screen, session.annotations, 'image');
			facts.push({ label: 'Image', value: `${image!.size} bytes` });
			step = `Sending to ${webhook.name}`;
			const link = await postWebhook(webhook, { id, title, image: image!, report });
			onposted(items, { text: `Sent to ${webhook.name}`, link });
		} catch (error) {
			const elapsed = { label: 'Elapsed', value: `${((performance.now() - started) / 1000).toFixed(1)} s` };
			problem = Problem.from(error).with(
				[{ label: 'Step', value: step }, elapsed],
				[...facts, ...session.capture.environment.map(entry => ({ label: entry.name, value: entry.value }))],
			);
		}
	}

	void post();
</script>

<div class="scrim" role="presentation">
	<div class="sheet" role="dialog" tabindex="-1" aria-label="Send to {webhook.name}">
		<h2>{webhook.name}</h2>
		{#if problem}
			<ProblemCard {problem} />
			<button type="button" class="strong" onclick={() => void post()}>Retry</button>
			<button type="button" onclick={onclose}>Cancel</button>
		{:else}
			<p role="status">{step}…</p>
		{/if}
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
		display: grid;
		gap: 8px;
		width: min(100%, 480px);
		max-height: 85%;
		border-radius: 16px 16px 0 0;
		padding: 16px;
		box-sizing: border-box;
		background: #1f1f1f;
		overflow: auto;
	}

	h2 {
		margin: 0;
		font-size: 16px;
		text-align: center;
	}

	p {
		margin: 0;
		color: #aeaeb2;
		text-align: center;
	}

	button {
		border: 0;
		border-radius: 12px;
		padding: 12px;
		background: #2c2c2e;
		color: inherit;
		font: inherit;
		cursor: pointer;
	}

	.strong {
		background: #0a84ff;
		font-weight: 600;
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
