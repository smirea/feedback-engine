import { feedback } from '@stefan.inc/feedback-engine/react';
import { store } from '../store.ts';

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

function draw(canvas: HTMLCanvasElement | null, done: Series) {
	if (!canvas) return;
	const context = canvas.getContext('2d')!;
	const width = canvas.width / done.values.length;
	context.clearRect(0, 0, canvas.width, canvas.height);
	context.fillStyle = '#7dd3b0';
	for (const [index, value] of done.values.entries()) {
		context.fillRect(index * width + 8, canvas.height - value * 30 - 4, width - 16, value * 30);
	}
}

export function MediaScreen() {
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
	const elsewhere = new URL('/icon.svg', location.href);
	elsewhere.hostname = elsewhere.hostname === 'localhost' ? '127.0.0.1' : 'localhost';

	return (
		<main className='screen media'>
			<title>Media</title>
			<h1>Media</h1>

			<section aria-labelledby='charts'>
				<h2 id='charts'>Charts</h2>
				<div className='tiles'>
					<figure className='card tile' ref={feedback('OpenChart', () => ({ series: open }))}>
						<svg viewBox={`0 0 ${open.values.length * 40} 100`} role='img' aria-label='Open todos per list'>
							{open.values.map((value, index) => (
								<rect
									key={index}
									x={index * 40 + 6}
									y={100 - (value / top) * 96}
									width='28'
									height={(value / top) * 96}
									rx='4'
								/>
							))}
						</svg>
						<figcaption className='muted'>Open, drawn as SVG</figcaption>
					</figure>
					<figure className='card tile' ref={feedback('DoneChart', () => ({ series: done }))}>
						<canvas
							width='240'
							height='100'
							aria-label='Done todos per list'
							ref={canvas => draw(canvas, done)}
						></canvas>
						<figcaption className='muted'>Done, drawn on a canvas</figcaption>
					</figure>
				</div>
			</section>

			<section aria-labelledby='images'>
				<h2 id='images'>Images</h2>
				<div className='tiles'>
					<figure className='card tile'>
						<img src='/icon.svg' alt='Feedback icon' width='96' height='96' />
						<figcaption className='muted'>From this origin</figcaption>
					</figure>
					<figure className='card tile'>
						<img src={elsewhere.href} alt='Feedback icon from another origin' width='96' height='96' />
						<figcaption className='muted'>From another origin</figcaption>
					</figure>
					<figure className='card tile'>
						<img src='/icon.svg' alt='' width='96' height='96' />
						<figcaption className='muted'>Decorative, with an empty alt</figcaption>
					</figure>
				</div>
			</section>
		</main>
	);
}
