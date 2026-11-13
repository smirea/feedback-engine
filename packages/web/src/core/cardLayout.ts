import type { Frame, Point, Size } from './model.ts';

export const cards = {
	margin: 24,
	column: 280,
	gutter: 36,
	spacing: 12,
	badge: 20,
	padding: 10,
	rightColumnPenalty: 80,
};

export type Card = { isLeft: boolean; origin: Point };
export type Layout = { shot: Frame; cards: Card[]; environment: Point; size: Size };

/** From the card's badge to the nearest side of the target, at the badge's height when the target spans it. */
export function line(card: Card, target: Frame): { start: Point; end: Point } {
	const start = {
		x: card.isLeft ? card.origin.x + cards.column : card.origin.x,
		y: card.origin.y + cards.padding + cards.badge / 2,
	};
	const end = {
		x: card.isLeft ? target.x : target.x + target.width,
		y: Math.min(Math.max(start.y, target.y + 2), target.y + target.height - 2),
	};
	return { start, end };
}

const length = (card: Card, target: Frame) => {
	const { start, end } = line(card, target);
	return Math.hypot(end.x - start.x, end.y - start.y);
};

/**
 * Where the image export puts each item's card. A card sits in the left column, as level with its target as the cards
 * above it allow. It moves to the right column when that makes its line to the target at least `rightColumnPenalty`
 * points shorter, as for a button at the right edge. The environment always sits at the top of the right column, and
 * right-column cards start below it. A tall capture is cut half the height that was on screen below the lowest box or
 * card, and never shorter than that height, and `shot` is the part that is drawn. `targets` and
 * `references` are frames in the capture. The layout's frames are in the image.
 */
export function place(
	targets: Frame[],
	heights: number[],
	screen: Size,
	environmentHeight: number,
	viewport: number,
	references: Frame[] = [],
): Layout {
	const { margin, column, gutter, spacing, rightColumnPenalty } = cards;
	const shot = { x: margin + column + gutter, y: margin, width: screen.width, height: screen.height };
	const rightX = shot.x + shot.width + gutter;
	const moved = targets.map(target => ({ ...target, x: target.x + shot.x, y: target.y + shot.y }));
	const midY = (index: number) => moved[index]!.y + moved[index]!.height / 2;
	const placed: Card[] = moved.map(() => ({ isLeft: true, origin: { x: 0, y: 0 } }));
	let nextLeft = margin;
	let nextRight = margin + environmentHeight + spacing * 2;
	const order = moved.map((_, index) => index).toSorted((a, b) => midY(a) - midY(b) || a - b);
	for (const index of order) {
		const desired = Math.max(midY(index) - heights[index]! / 2, margin);
		const left: Card = { isLeft: true, origin: { x: margin, y: Math.max(desired, nextLeft) } };
		const right: Card = { isLeft: false, origin: { x: rightX, y: Math.max(desired, nextRight) } };
		const card = length(left, moved[index]!) - length(right, moved[index]!) >= rightColumnPenalty ? right : left;
		placed[index] = card;
		if (card.isLeft) nextLeft = card.origin.y + heights[index]! + spacing;
		else nextRight = card.origin.y + heights[index]! + spacing;
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
		environment: { x: rightX, y: margin },
		size: { width: rightX + column + margin, height },
	};
}
