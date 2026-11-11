<svelte:options css="injected" />

<script lang="ts">
	let { onpress }: { onpress: () => void } = $props();
</script>

<!-- A click must not take focus from the field the user was typing in. -->
<button class="pill" type="button" onmousedown={event => event.preventDefault()} onclick={onpress}>
	<svg viewBox="0 0 256 256" aria-hidden="true">
		<path d="M40 56h120l24 24v64H96l-32 28v-28H40z" />
		<path d="M112 172v20h64l32 28v-28h20v-88l-16-16" />
	</svg>
	Add Feedback
</button>

<style>
	.pill {
		position: fixed;
		top: max(10px, env(safe-area-inset-top));
		left: 50%;
		z-index: 2147483647;
		display: flex;
		align-items: center;
		gap: 8px;
		border: 1px solid rgb(255 255 255 / 0.35);
		border-radius: 999px;
		padding: 10px 18px 10px 14px;
		background: rgb(40 40 44 / 0.72);
		backdrop-filter: blur(18px) saturate(1.6);
		-webkit-backdrop-filter: blur(18px) saturate(1.6);
		box-shadow: 0 8px 28px rgb(0 0 0 / 0.28);
		color: white;
		font:
			600 15px/1 system-ui,
			sans-serif;
		cursor: pointer;
		translate: -50% 0;
		animation: drop 0.35s cubic-bezier(0.2, 0.9, 0.3, 1.2);
	}

	svg {
		width: 22px;
		height: 22px;
		fill: none;
		stroke: currentColor;
		stroke-width: 16;
		stroke-linejoin: round;
	}

	@keyframes drop {
		from {
			opacity: 0;
			scale: 0.5 0.6;
			translate: -50% -24px;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.pill {
			animation: none;
		}
	}
</style>
