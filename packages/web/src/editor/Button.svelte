<svelte:options css="injected" />

<script lang="ts">
	let { onpress }: { onpress: () => void } = $props();

	const size = 44;
	const margin = 12;
	const storageKey = 'feedback-engine:button';

	type Place = { side: 'left' | 'right'; top: number };
	function saved(): Place | undefined {
		try {
			const place = JSON.parse(localStorage.getItem(storageKey) ?? 'null') as Place | null;
			return place && (place.side === 'left' || place.side === 'right') && Number.isFinite(place.top)
				? place
				: undefined;
		} catch {
			return undefined;
		}
	}

	let place = $state(saved());
	let dragging = $state<{ x: number; y: number }>();
	let start: { x: number; y: number } | undefined;
	let moved = false;

	const clamp = (top: number) => Math.min(Math.max(top, margin), innerHeight - size - margin);

	function down(event: PointerEvent) {
		start = { x: event.clientX, y: event.clientY };
		moved = false;
		(event.currentTarget as Element).setPointerCapture(event.pointerId);
	}

	function move(event: PointerEvent) {
		if (!start) return;
		// A tap wobbles by a few pixels, and must still read as a tap.
		if (!moved && Math.hypot(event.clientX - start.x, event.clientY - start.y) < 8) return;
		moved = true;
		dragging = { x: event.clientX - size / 2, y: event.clientY - size / 2 };
	}

	function up(event: PointerEvent) {
		if (!start) return;
		start = undefined;
		if (!moved) return;
		place = { side: event.clientX < innerWidth / 2 ? 'left' : 'right', top: clamp(event.clientY - size / 2) };
		dragging = undefined;
		try {
			localStorage.setItem(storageKey, JSON.stringify(place));
		} catch {
			// A private window can refuse storage. The button then starts in its corner next time.
		}
	}

	const style = $derived(
		dragging
			? `left: ${dragging.x}px; top: ${dragging.y}px; bottom: auto; transition: none;`
			: place
				? `${place.side}: max(${margin}px, env(safe-area-inset-${place.side})); top: ${clamp(place.top)}px; bottom: auto;`
				: '',
	);
</script>

<!-- A click must not take focus from the field the user was typing in. -->
<button
	class="button"
	type="button"
	aria-label="Feedback"
	{style}
	onmousedown={event => event.preventDefault()}
	onpointerdown={down}
	onpointermove={move}
	onpointerup={up}
	onpointercancel={() => ((start = undefined), (dragging = undefined))}
	onclick={() => {
		if (!moved) onpress();
		moved = false;
	}}
>
	<svg viewBox="0 0 256 256" aria-hidden="true">
		<path d="M40 56h120l24 24v64H96l-32 28v-28H40z" />
		<path d="M112 172v20h64l32 28v-28h20v-88l-16-16" />
	</svg>
</button>

<style>
	.button {
		position: fixed;
		right: max(12px, env(safe-area-inset-right));
		bottom: max(24px, calc(env(safe-area-inset-bottom) + 12px));
		z-index: 2147483646;
		display: grid;
		place-items: center;
		width: 44px;
		height: 44px;
		border: 1px solid rgb(255 255 255 / 0.35);
		border-radius: 50%;
		padding: 0;
		background: rgb(40 40 44 / 0.6);
		backdrop-filter: blur(18px) saturate(1.6);
		-webkit-backdrop-filter: blur(18px) saturate(1.6);
		box-shadow: 0 6px 20px rgb(0 0 0 / 0.25);
		color: white;
		cursor: pointer;
		/* A drag moves the button instead of scrolling the page. */
		touch-action: none;
		-webkit-tap-highlight-color: transparent;
		user-select: none;
		-webkit-user-select: none;
		transition:
			left 0.2s,
			right 0.2s,
			top 0.2s;
	}

	svg {
		width: 22px;
		height: 22px;
		fill: none;
		stroke: currentColor;
		stroke-width: 16;
		stroke-linejoin: round;
	}
</style>
