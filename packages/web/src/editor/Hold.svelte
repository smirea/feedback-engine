<svelte:options css="injected" />

<script lang="ts">
	import { holdDelay, holdDuration } from '../dom/hold.ts';
</script>

<!-- It grows for exactly the rest of the hold, so it is full when the capture starts. -->
<div class="hold" role="status" aria-label="Hold for Feedback" style="--grow:{holdDuration - holdDelay}ms">
	<span class="fill"></span>
	<span class="label">
		<svg viewBox="0 0 256 256" aria-hidden="true">
			<path d="M40 56h120l24 24v64H96l-32 28v-28H40z" />
			<path d="M112 172v20h64l32 28v-28h20v-88l-16-16" />
		</svg>
		Add Feedback
	</span>
</div>

<style>
	.hold {
		position: fixed;
		top: max(10px, env(safe-area-inset-top));
		left: 50%;
		z-index: 2147483647;
		display: grid;
		place-items: center;
		width: 176px;
		height: 42px;
		border: 1px solid rgb(255 255 255 / 0.35);
		border-radius: 999px;
		box-sizing: border-box;
		background: rgb(40 40 44 / 0.72);
		backdrop-filter: blur(18px) saturate(1.6);
		-webkit-backdrop-filter: blur(18px) saturate(1.6);
		box-shadow: 0 8px 28px rgb(0 0 0 / 0.28);
		color: white;
		overflow: hidden;
		pointer-events: none;
		translate: -50% 0;
		animation:
			grow var(--grow) cubic-bezier(0.3, 0.7, 0.4, 1) both,
			ready 0.5s var(--grow) ease-in-out infinite alternate;
	}

	.fill {
		position: absolute;
		inset: 0;
		background: linear-gradient(90deg, rgb(10 132 255 / 0.55), rgb(100 210 255 / 0.55));
		transform-origin: left;
		animation: fill var(--grow) linear both;
	}

	.label {
		position: relative;
		display: flex;
		align-items: center;
		gap: 8px;
		font:
			600 15px/1 system-ui,
			sans-serif;
		white-space: nowrap;
		animation: appear var(--grow) ease-out both;
	}

	svg {
		width: 22px;
		height: 22px;
		fill: none;
		stroke: currentColor;
		stroke-width: 16;
		stroke-linejoin: round;
	}

	/* From a capsule the size of a phone's camera cutout to the size of the Add Feedback pill. */
	@keyframes grow {
		from {
			width: 44px;
			height: 14px;
			opacity: 0.4;
		}
	}

	@keyframes fill {
		from {
			scale: 0 1;
		}
	}

	@keyframes appear {
		0%,
		45% {
			opacity: 0;
			scale: 0.8;
		}
	}

	@keyframes ready {
		to {
			box-shadow: 0 0 0 4px rgb(10 132 255 / 0.35);
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.hold {
			animation: none;
		}

		.label {
			animation: none;
		}
	}
</style>
