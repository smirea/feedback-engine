<script lang="ts">
	import { feedback } from '@smirea/feedback-engine/svelte';
	import { store } from '../../lib/store.svelte';

	/** Reads as one line in a capture instead of its fields. */
	class Series {
		name: string;
		values: number[];

		constructor(name: string, values: number[]) {
			this.name = name;
			this.values = values;
		}

		toFeedback() {
			return `${this.name}: ${this.values.join(', ')}`;
		}
	}

	const done = new Series(
		'Done per list',
		store.lists.map(list => list.items.filter(item => item.isDone).length),
	);
	const open = new Series(
		'Open per list',
		store.lists.map(list => list.items.filter(item => !item.isDone).length),
	);
	const top = Math.max(...open.values, 1);

	// The same file from another origin: the page's host with the other loopback name.
	const elsewhere = $derived.by(() => {
		if (typeof location === 'undefined') return '';
		const url = new URL('/icon.svg', location.href);
		url.hostname = url.hostname === 'localhost' ? '127.0.0.1' : 'localhost';
		return url.href;
	});

	function draw(canvas: HTMLCanvasElement) {
		const context = canvas.getContext('2d')!;
		const width = canvas.width / done.values.length;
		context.fillStyle = '#7dd3b0';
		for (const [index, value] of done.values.entries()) {
			context.fillRect(index * width + 8, canvas.height - value * 30 - 4, width - 16, value * 30);
		}
	}
</script>

<svelte:head>
	<title>Media</title>
</svelte:head>

<main class="screen" {@attach feedback('MediaScreen')}>
	<h1>Media</h1>

	<section aria-labelledby="charts">
		<h2 id="charts">Charts</h2>
		<div class="tiles">
			<figure class="card tile" {@attach feedback('OpenChart', () => ({ series: open }))}>
				<svg viewBox="0 0 {open.values.length * 40} 100" role="img" aria-label="Open todos per list">
					{#each open.values as value, index (index)}
						<rect x={index * 40 + 6} y={100 - (value / top) * 96} width="28" height={(value / top) * 96} rx="4" />
					{/each}
				</svg>
				<figcaption class="muted">Open, drawn as SVG</figcaption>
			</figure>
			<figure class="card tile" {@attach feedback('DoneChart', () => ({ series: done }))}>
				<canvas width="240" height="100" aria-label="Done todos per list" {@attach draw}></canvas>
				<figcaption class="muted">Done, drawn on a canvas</figcaption>
			</figure>
		</div>
	</section>

	<section aria-labelledby="images">
		<h2 id="images">Images</h2>
		<div class="tiles">
			<figure class="card tile">
				<img src="/icon.svg" alt="Feedback icon" width="96" height="96" />
				<figcaption class="muted">From this origin</figcaption>
			</figure>
			<figure class="card tile">
				<img src={elsewhere} alt="Feedback icon from another origin" width="96" height="96" />
				<figcaption class="muted">From another origin</figcaption>
			</figure>
			<figure class="card tile">
				<img src="/icon.svg" alt="" width="96" height="96" />
				<figcaption class="muted">Decorative, with an empty alt</figcaption>
			</figure>
		</div>
	</section>
</main>

<style>
	.tiles {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(11rem, 1fr));
		gap: 0.75rem;
	}

	.tile {
		display: grid;
		justify-items: center;
		gap: 0.5rem;
		padding: 1rem;
	}

	.tile > :global(*) {
		border-top: 0;
	}

	svg,
	canvas {
		width: 100%;
		height: 6.25rem;
	}

	rect {
		fill: var(--app-accent);
	}
</style>
