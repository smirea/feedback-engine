import {
	cards as metrics,
	connector,
	nearestSource,
	paletteColor,
	place,
	tag,
	title,
	type Annotations,
	type Card,
	type Frame,
	type Point,
} from '../core/index.ts';
import type { Screen } from './capture.ts';
import { githubPath } from './webhook.ts';

/** Keeps a tall full-length capture shareable. */
const pixelBudget = 40_000_000;
const secondary = '#6b6b6b';
const primary = '#141414';
const sans = 'system-ui, -apple-system, "Segoe UI", sans-serif';
const mono = 'ui-monospace, "SF Mono", Menlo, Consolas, monospace';
const repository = 'github.com/smirea/feedback-engine';

type Run = { text: string; font: string; color: string; background?: string; spacing?: number };
type Piece = Run & { x: number; width: number };
type Line = { pieces: Piece[]; height: number; gap: number };

const fontSize = (font: string) => Number(/(\d+(?:\.\d+)?)px/.exec(font)![1]);

/**
 * Breaks runs of styled text into lines no wider than `width`. A paragraph ends at each newline, with `gap` points after
 * it, and `before` points more before it.
 */
function layout(
	context: CanvasRenderingContext2D,
	paragraphs: { runs: Run[]; gap?: number; before?: number }[],
	width: number,
): Line[] {
	const lines: Line[] = [];
	for (const paragraph of paragraphs) {
		if (paragraph.before && lines.length) lines.at(-1)!.gap += paragraph.before;
		let current: Line = { pieces: [], height: 0, gap: 0 };
		let x = 0;
		const wrap = () => {
			lines.push(current);
			current = { pieces: [], height: 0, gap: 0 };
			x = 0;
		};
		for (const run of paragraph.runs) {
			context.font = run.font;
			context.letterSpacing = `${run.spacing ?? 0}px`;
			const height = Math.ceil(fontSize(run.font) * 1.3);
			// A highlighted token stays whole. Other text breaks between words, and a word wider than the line breaks inside.
			const words = run.background ? [run.text] : (run.text.match(/\n|[^\S\n]+|[^\s]+/g) ?? []);
			for (let word of words) {
				if (word === '\n') {
					current.height ||= height;
					wrap();
					continue;
				}
				let wordWidth = context.measureText(word).width;
				if (x + wordWidth > width && x > 0) {
					wrap();
					if (!word.trim()) continue;
				}
				while (wordWidth > width && word.length > 1) {
					let count = word.length - 1;
					while (count > 1 && context.measureText(word.slice(0, count)).width > width) count -= 1;
					const head = word.slice(0, count);
					current.pieces.push({ ...run, text: head, x: 0, width: context.measureText(head).width });
					current.height = Math.max(current.height, height);
					wrap();
					word = word.slice(count);
					wordWidth = context.measureText(word).width;
				}
				current.pieces.push({ ...run, text: word, x, width: wordWidth });
				current.height = Math.max(current.height, height);
				x += wordWidth;
			}
		}
		if (current.pieces.length) lines.push(current);
		if (lines.length) lines.at(-1)!.gap = paragraph.gap ?? 0;
	}
	context.letterSpacing = '0px';
	return lines;
}

const heightOf = (lines: Line[]) => Math.ceil(lines.reduce((sum, row) => sum + row.height + row.gap, 0));

function drawText(context: CanvasRenderingContext2D, lines: Line[], origin: Point) {
	let y = origin.y;
	context.textBaseline = 'middle';
	for (const row of lines) {
		for (const piece of row.pieces) {
			context.font = piece.font;
			context.letterSpacing = `${piece.spacing ?? 0}px`;
			if (piece.background) {
				context.fillStyle = piece.background;
				context.fillRect(origin.x + piece.x, y, piece.width, row.height);
			}
			context.fillStyle = piece.color;
			context.fillText(piece.text, origin.x + piece.x, y + row.height / 2);
		}
		y += row.height + row.gap;
	}
	context.letterSpacing = '0px';
}

function roundedRect(context: CanvasRenderingContext2D, frame: Frame, radius: number) {
	context.beginPath();
	context.roundRect(frame.x, frame.y, frame.width, frame.height, Math.min(radius, frame.width / 2, frame.height / 2));
}

function withAlpha(color: string, alpha: number) {
	const value = Number.parseInt(color.slice(1), 16);
	return `rgb(${value >> 16} ${(value >> 8) & 255} ${value & 255} / ${alpha})`;
}

/** The card's border and its footer's fill: the item's color at 45% over white, opaque so the two match exactly. */
function tint(color: string) {
	const value = Number.parseInt(color.slice(1), 16);
	const mix = (channel: number) => Math.round(channel * 0.45 + 255 * 0.55);
	return `rgb(${mix(value >> 16)} ${mix((value >> 8) & 255)} ${mix(value & 255)})`;
}

const footerPadding = 6;

const clamp = (value: number, low: number, high: number) => Math.min(Math.max(value, low), high);

function dashedBox(context: CanvasRenderingContext2D, target: Frame, color: string) {
	roundedRect(context, { x: target.x - 1, y: target.y - 1, width: target.width + 2, height: target.height + 2 }, 4);
	context.lineWidth = 1.5;
	context.setLineDash([6, 4]);
	context.strokeStyle = withAlpha(color, 0.9);
	context.stroke();
	context.setLineDash([]);
}

function label(context: CanvasRenderingContext2D, text: string, center: Point) {
	context.font = `700 11px ${sans}`;
	context.fillStyle = 'white';
	context.textAlign = 'center';
	context.textBaseline = 'middle';
	context.fillText(text, center.x, center.y + 0.5);
	context.textAlign = 'left';
}

function badge(context: CanvasRenderingContext2D, number: number, color: string, center: Point) {
	context.beginPath();
	context.arc(center.x, center.y, metrics.badge / 2, 0, Math.PI * 2);
	context.fillStyle = color;
	context.fill();
	context.lineWidth = 1.5;
	context.strokeStyle = 'white';
	context.stroke();
	label(context, String(number), center);
}

/** A reference's `@N`, in a square centered on the box's top-right corner. */
function referenceTag(context: CanvasRenderingContext2D, text: string, color: string, corner: Point, shot: Frame) {
	context.font = `700 11px ${sans}`;
	const width = Math.max(context.measureText(text).width + 8, metrics.badge);
	const center = {
		x: clamp(corner.x, shot.x + width / 2 + 2, shot.x + shot.width - width / 2 - 2),
		y: clamp(corner.y, shot.y + metrics.badge / 2 + 2, shot.y + shot.height - metrics.badge / 2 - 2),
	};
	roundedRect(context, { x: center.x - width / 2, y: center.y - metrics.badge / 2, width, height: metrics.badge }, 3);
	context.fillStyle = color;
	context.fill();
	context.lineWidth = 1.5;
	context.strokeStyle = 'white';
	context.stroke();
	label(context, text, center);
}

/** GitHub's mark and the repository, faint, against the strip's left or right edge. */
function watermark(context: CanvasRenderingContext2D, { isLeft, origin }: Card) {
	const side = metrics.watermark;
	context.font = `11px ${sans}`;
	const width = side + 6 + context.measureText(repository).width;
	const x = isLeft ? origin.x : origin.x + metrics.column - width;
	context.fillStyle = withAlpha(secondary, 0.5);
	context.save();
	context.translate(x, origin.y);
	const mark = new Path2D(githubPath);
	context.fill(mark);
	context.restore();
	context.textBaseline = 'middle';
	context.fillText(repository, x + side + 6, origin.y + side / 2);
}

/**
 * The image export: the screenshot with numbered boxes, each item's text and code location in a card beside it, a
 * tagged box for each referenced node, and the capture's environment, so the one file is enough on its own.
 */
export function annotatedImage({ capture, image, scale }: Screen, annotations: Annotations): HTMLCanvasElement {
	const { column, padding, badge: badgeSize } = metrics;
	const textWidth = column - padding * 3 - badgeSize;
	const canvas = document.createElement('canvas');
	const context = canvas.getContext('2d')!;

	const app = capture.environment.find(entry => entry.name === 'App')?.value ?? 'App';
	const flagged = new Set(annotations.items.map(item => item.target));
	const unflagged = annotations.used.filter(reference => !flagged.has(reference.target));
	const environment = layout(
		context,
		[
			{ runs: [{ text: `Feedback: ${app}`, font: `700 16px ${sans}`, color: primary }], gap: 8 },
			...capture.environment
				.filter(entry => entry.name !== 'App')
				.map(entry => ({
					runs: [
						{ text: `${entry.name}: `, font: `600 12.5px ${sans}`, color: secondary },
						{ text: entry.value, font: `12.5px ${sans}`, color: primary },
					],
					gap: 4,
				})),
			...(unflagged.length
				? [
						{
							runs: [{ text: 'REFERENCES', font: `700 11px ${sans}`, color: secondary, spacing: 0.6 }],
							before: 6,
							gap: 4,
						},
					]
				: []),
			...unflagged.map(reference => {
				const source = nearestSource(capture, reference.target);
				return {
					runs: [
						{
							text: ` ${tag(reference)} `,
							font: `700 11px ${sans}`,
							color: 'white',
							background: paletteColor(annotations.colorIndex(reference.target)),
						},
						...(source ? [{ text: ` ${source}`, font: `11px ${mono}`, color: primary }] : []),
						{ text: ` ${title(capture.nodes[reference.target]!)}`, font: `12.5px ${sans}`, color: primary },
					],
					gap: 4,
				};
			}),
		],
		column,
	);
	const environmentHeight = heightOf(environment);

	const items = annotations.items.map(item => {
		const node = capture.nodes[item.target]!;
		const source = nearestSource(capture, item.target);
		const text = layout(
			context,
			[
				{
					runs: annotations.segments(item.text).map(segment =>
						segment.reference
							? {
									text: ` ${segment.text} `,
									font: `600 14px ${sans}`,
									color: 'white',
									background: paletteColor(annotations.colorIndex(segment.reference.target)),
								}
							: { text: segment.text, font: `14px ${sans}`, color: primary },
					),
				},
			],
			textWidth,
		);
		const footer = layout(
			context,
			[
				{ runs: [{ text: title(node), font: `600 11px ${sans}`, color: primary }] },
				...(source ? [{ runs: [{ text: source, font: `11px ${mono}`, color: primary }] }] : []),
			],
			column - padding * 2,
		);
		const body = Math.max(heightOf(text), badgeSize) + padding * 2;
		const footerHeight = heightOf(footer) + footerPadding * 2;
		return {
			number: annotations.number(item.target),
			color: paletteColor(annotations.colorIndex(item.target)),
			text,
			footer,
			body,
			height: body + footerHeight,
			frame: node.frame,
		};
	});

	const placed = place(
		items.map(item => item.frame),
		items.map(item => item.height),
		capture.size,
		environmentHeight,
		capture.visible.height,
		annotations.used.map(reference => capture.nodes[reference.target]!.frame),
	);
	const { shot, size } = placed;
	const exportScale = Math.min(scale, Math.sqrt(pixelBudget / (size.width * size.height)));
	canvas.width = Math.round(size.width * exportScale);
	canvas.height = Math.round(size.height * exportScale);
	context.scale(exportScale, exportScale);

	context.fillStyle = '#f2f2f2';
	context.fillRect(0, 0, size.width, size.height);
	context.save();
	roundedRect(context, shot, 12);
	context.clip();
	context.drawImage(image, shot.x, shot.y, capture.size.width, capture.size.height);
	context.restore();
	roundedRect(context, shot, 12);
	context.lineWidth = 1;
	context.strokeStyle = '#cccccc';
	context.stroke();

	const inShot = (frame: Frame) => ({ ...frame, x: frame.x + shot.x, y: frame.y + shot.y });
	for (const [index, item] of items.entries()) {
		const target = inShot(item.frame);
		dashedBox(context, target, item.color);
		const { start, control1, control2, end } = connector(placed.cards[index]!, target);
		context.beginPath();
		context.moveTo(start.x, start.y);
		context.bezierCurveTo(control1.x, control1.y, control2.x, control2.y, end.x, end.y);
		context.lineWidth = 1.25;
		context.strokeStyle = withAlpha(item.color, 0.6);
		context.stroke();
		context.beginPath();
		context.arc(end.x, end.y, 2.5, 0, Math.PI * 2);
		context.fillStyle = item.color;
		context.fill();
		badge(context, item.number, item.color, {
			x: clamp(target.x, shot.x + badgeSize / 2 + 2, shot.x + shot.width - badgeSize / 2 - 2),
			y: clamp(target.y, shot.y + badgeSize / 2 + 2, shot.y + shot.height - badgeSize / 2 - 2),
		});
	}

	for (const reference of annotations.used) {
		const color = paletteColor(annotations.colorIndex(reference.target));
		const target = inShot(capture.nodes[reference.target]!.frame);
		if (!flagged.has(reference.target)) dashedBox(context, target, color);
		referenceTag(context, tag(reference), color, { x: target.x + target.width, y: target.y }, shot);
	}

	for (const [index, item] of items.entries()) {
		const { origin } = placed.cards[index]!;
		const border = tint(item.color);
		roundedRect(context, { ...origin, width: column, height: item.height }, 10);
		context.fillStyle = 'white';
		context.fill();
		context.save();
		context.clip();
		context.fillStyle = border;
		context.fillRect(origin.x, origin.y + item.body, column, item.height - item.body);
		context.restore();
		roundedRect(context, { ...origin, width: column, height: item.height }, 10);
		context.lineWidth = 1;
		context.strokeStyle = border;
		context.stroke();
		badge(context, item.number, item.color, {
			x: origin.x + padding + badgeSize / 2,
			y: origin.y + padding + badgeSize / 2,
		});
		drawText(context, item.text, { x: origin.x + padding * 2 + badgeSize, y: origin.y + padding });
		drawText(context, item.footer, { x: origin.x + padding, y: origin.y + item.body + footerPadding });
	}

	drawText(context, environment, placed.environment);
	watermark(context, placed.watermark);
	return canvas;
}
