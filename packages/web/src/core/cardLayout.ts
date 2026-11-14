import type { Frame, Point, Size } from './model.ts';

export const cards = {
	margin: 24,
	column: 280,
	gutter: 36,
	spacing: 12,
	badge: 20,
	padding: 10,
	rightColumnPenalty: 80,
	crossingPenalty: 500,
	watermark: 13,
};

export type Card = { isLeft: boolean; origin: Point };
/** `watermark` is the top-left of a column-wide strip `cards.watermark` tall, aligned to its left or right edge. */
export type Layout = { shot: Frame; cards: Card[]; environment: Point; watermark: Card; size: Size };
export type Curve = { start: Point; control1: Point; control2: Point; end: Point };

/**
 * An S curve from the card's badge to the nearest side of the target, at the badge's height when the target spans it.
 * It leaves the card and meets the target level.
 */
export function connector(card: Card, target: Frame): Curve {
	const start = {
		x: card.isLeft ? card.origin.x + cards.column : card.origin.x,
		y: card.origin.y + cards.padding + cards.badge / 2,
	};
	const end = {
		x: card.isLeft ? target.x : target.x + target.width,
		y: Math.min(Math.max(start.y, target.y + 2), target.y + target.height - 2),
	};
	const bend = (end.x - start.x) / 2;
	return { start, control1: { x: start.x + bend, y: start.y }, control2: { x: end.x - bend, y: end.y }, end };
}

const samples = 16;

function polyline({ start, control1, control2, end }: Curve): Point[] {
	return Array.from({ length: samples + 1 }, (_, step) => {
		const t = step / samples;
		const u = 1 - t;
		const at = (a: number, b: number, c: number, d: number) =>
			u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d;
		return { x: at(start.x, control1.x, control2.x, end.x), y: at(start.y, control1.y, control2.y, end.y) };
	});
}

function segmentCrossesBox(a: Point, b: Point, box: Frame) {
	let low = 0;
	let high = 1;
	const dx = b.x - a.x;
	const dy = b.y - a.y;
	const edges: [number, number][] = [
		[-dx, a.x - box.x],
		[dx, box.x + box.width - a.x],
		[-dy, a.y - box.y],
		[dy, box.y + box.height - a.y],
	];
	for (const [direction, distance] of edges) {
		if (direction === 0) {
			if (distance < 0) return false;
			continue;
		}
		const t = distance / direction;
		if (direction < 0) low = Math.max(low, t);
		else high = Math.min(high, t);
		if (low > high) return false;
	}
	return true;
}

const turn = (a: Point, b: Point, c: Point) => Math.sign((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x));
const segmentsCross = (a: Point, b: Point, c: Point, d: Point) =>
	turn(a, b, c) * turn(a, b, d) < 0 && turn(c, d, a) * turn(c, d, b) < 0;

const contains = (box: Frame, point: Point) =>
	point.x >= box.x && point.x <= box.x + box.width && point.y >= box.y && point.y <= box.y + box.height;

/** Boxes the path passes through, other than its target and the boxes around it, plus the earlier paths it crosses. */
function crossings(path: Point[], target: Frame, boxes: Frame[], earlier: Point[][]) {
	const end = path.at(-1)!;
	const pairs = path.slice(1).map((point, index) => [path[index]!, point] as const);
	const box = boxes.filter(
		box =>
			!contains(box, end) &&
			!(box.x === target.x && box.y === target.y && box.width === target.width && box.height === target.height) &&
			pairs.some(([a, b]) => segmentCrossesBox(a, b, box)),
	).length;
	const paths = earlier.filter(other =>
		other.slice(1).some((d, index) => pairs.some(([a, b]) => segmentsCross(a, b, other[index]!, d))),
	).length;
	return box + paths;
}

type Columns = 'both' | 'left' | 'right';
type Arrangement = Layout & { cost: number; crossings: number };

function arrange(
	columns: Columns,
	targets: Frame[],
	heights: number[],
	screen: Size,
	environmentHeight: number,
	viewport: number,
	references: Frame[],
): Arrangement {
	const { margin, column, gutter, spacing, rightColumnPenalty, crossingPenalty, watermark } = cards;
	const top = margin + watermark + spacing;
	const shot = {
		x: columns === 'right' ? margin : margin + column + gutter,
		y: top,
		width: screen.width,
		height: screen.height,
	};
	const rightX = shot.x + shot.width + gutter;
	const inShot = (frame: Frame) => ({ ...frame, x: frame.x + shot.x, y: frame.y + shot.y });
	const moved = targets.map(inShot);
	const boxes = [...moved, ...references.map(inShot)];
	const midY = (index: number) => moved[index]!.y + moved[index]!.height / 2;
	const placed: Card[] = moved.map(() => ({ isLeft: true, origin: { x: 0, y: 0 } }));
	const paths: Point[][] = [];
	const environment = { x: columns === 'left' ? margin : rightX, y: top };
	const underEnvironment = top + environmentHeight + spacing * 2;
	let nextLeft = columns === 'left' ? underEnvironment : top;
	let nextRight = underEnvironment;
	let cost = 0;
	let crossed = 0;
	const order = moved.map((_, index) => index).toSorted((a, b) => midY(a) - midY(b) || a - b);
	for (const index of order) {
		const target = moved[index]!;
		const desired = Math.max(midY(index) - heights[index]! / 2, top);
		const options: Card[] = [];
		if (columns !== 'right') options.push({ isLeft: true, origin: { x: margin, y: Math.max(desired, nextLeft) } });
		if (columns !== 'left') options.push({ isLeft: false, origin: { x: rightX, y: Math.max(desired, nextRight) } });
		const scored = options.map(card => {
			const curve = connector(card, target);
			const path = polyline(curve);
			const count = crossings(path, target, boxes, paths);
			const length = Math.hypot(curve.end.x - curve.start.x, curve.end.y - curve.start.y);
			const penalty = columns === 'both' && !card.isLeft ? rightColumnPenalty : 0;
			return { card, path, count, cost: length + penalty + count * crossingPenalty };
		});
		const best = scored.reduce((chosen, option) => (option.cost <= chosen.cost ? option : chosen));
		placed[index] = best.card;
		paths.push(best.path);
		cost += best.cost;
		crossed += best.count;
		if (best.card.isLeft) nextLeft = best.card.origin.y + heights[index]! + spacing;
		else nextRight = best.card.origin.y + heights[index]! + spacing;
	}

	const lowest = Math.max(
		0,
		...[...targets, ...references].map(frame => frame.y + frame.height),
		...placed.map((card, index) => card.origin.y + heights[index]! - shot.y),
	);
	shot.height = Math.min(screen.height, Math.max(viewport, lowest + viewport / 2));
	const height = Math.max(shot.y + shot.height, nextLeft - spacing, nextRight - spacing) + margin;
	return {
		shot,
		cards: placed,
		environment,
		watermark: { isLeft: columns === 'left', origin: { x: environment.x, y: margin } },
		size: { width: columns === 'left' ? shot.x + shot.width + margin : rightX + column + margin, height },
		cost,
		crossings: crossed,
	};
}

/**
 * Where the image export puts each item's card. Cards go in the column whose path to the target costs least: its
 * length, `rightColumnPenalty` points for the right column, and `crossingPenalty` for each other box or earlier path
 * it crosses, as level with the target as the cards above allow. The watermark has a strip across the top of the image,
 * in the outer corner of the environment's column. The environment sits at the top of the right column, and
 * right-column cards start below it. When one column holds the
 * environment and every card with no crossing and no taller image, the image drops the other column and keeps only a
 * margin on that side, and of the two sides it takes the one whose paths are shorter in total. A tall capture is cut half the
 * height that was on screen below the lowest box or card, and never shorter than that height, and `shot` is the part
 * that is drawn. `targets` and `references` are frames in the capture. The layout's frames are in the image.
 */
export function place(
	targets: Frame[],
	heights: number[],
	screen: Size,
	environmentHeight: number,
	viewport: number,
	references: Frame[] = [],
): Layout {
	const build = (columns: Columns) =>
		arrange(columns, targets, heights, screen, environmentHeight, viewport, references);
	const both = build('both');
	const single = [build('left'), build('right')]
		.filter(option => option.crossings === 0 && option.size.height <= both.size.height)
		.reduce<Arrangement | undefined>(
			(chosen, option) => (chosen && chosen.cost <= option.cost ? chosen : option),
			undefined,
		);
	const { shot, cards: placed, environment, watermark, size } = single ?? both;
	return { shot, cards: placed, environment, watermark, size };
}
