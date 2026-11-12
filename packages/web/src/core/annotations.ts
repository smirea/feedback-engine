import type { Node } from './model.ts';

export type FeedbackItem = { id: string; target: number; text: string };

/** A node that feedback text points at with a token such as `@1_Dialog`. */
export type Reference = { number: number; target: number; token: string };

export type Segment = { text: string; reference?: Reference };

export const tag = (reference: Reference) => `@${reference.number}`;

/**
 * Everything a share exports besides the capture. Items and references share one count: a node takes the next number
 * and color the first time it is flagged or referenced, and keeps them for the capture, so no two boxes show the same
 * number. Removing an item leaves its number unused, since tokens in other texts may still name it.
 */
export class Annotations {
	items: FeedbackItem[] = [];
	references: Reference[] = [];
	private marked: number[] = [];

	colorIndex(node: number) {
		const index = this.marked.indexOf(node);
		return index === -1 ? this.marked.length : index;
	}

	/** The node's number, or the one it would take next. */
	number(node: number) {
		return this.colorIndex(node) + 1;
	}

	/** Updates the target's item, or adds one. */
	submit(text: string, target: number) {
		const item = this.items.find(existing => existing.target === target);
		if (item) {
			item.text = text;
		} else {
			this.items.push({ id: crypto.randomUUID(), target, text });
			this.mark(target);
		}
	}

	remove(id: string) {
		this.items = this.items.filter(item => item.id !== id);
	}

	/** The node's reference. A node referenced again gets the same one. */
	reference(node: Node): Reference {
		const existing = this.references.find(reference => reference.target === node.id);
		if (existing) return existing;
		const words = node.name
			.split(/[^\p{L}\p{N}]+/u)
			.filter(Boolean)
			.join('_');
		this.mark(node.id);
		const number = this.number(node.id);
		const reference = { number, target: node.id, token: `@${number}_${words || 'Node'}` };
		this.references.push(reference);
		return reference;
	}

	private mark(node: number) {
		if (!this.marked.includes(node)) this.marked.push(node);
	}

	/** The references some item's text names, by number. */
	get used() {
		return this.referencesIn(this.items.map(item => item.text));
	}

	referencesIn(texts: string[]) {
		const tokens = new Set(texts.flatMap(text => this.segments(text).map(segment => segment.reference?.token)));
		return this.references.filter(reference => tokens.has(reference.token)).toSorted((a, b) => a.number - b.number);
	}

	/** The text split into plain runs and reference tokens. A token followed by more letters is plain text, since it names nothing. */
	segments(text: string): Segment[] {
		const segments: Segment[] = [];
		const plain = (run: string) => {
			if (!run) return;
			const last = segments.at(-1);
			if (last && !last.reference) last.text += run;
			else segments.push({ text: run });
		};
		let rest = 0;
		for (const match of text.matchAll(/@\d+_[\p{L}\p{N}_]+/gu)) {
			const reference = this.references.find(known => known.token === match[0]);
			if (reference) {
				plain(text.slice(rest, match.index));
				segments.push({ text: reference.token, reference });
			} else {
				plain(text.slice(rest, match.index + match[0].length));
			}
			rest = match.index + match[0].length;
		}
		plain(text.slice(rest));
		return segments;
	}
}

/** The colors items and references take, in order. They are iOS's system colors, so both platforms' exports match. */
export const palette = ['#FF3B30', '#007AFF', '#34C759', '#FF9500', '#AF52DE', '#FF2D55', '#30B0C7', '#5856D6'];

export const paletteColor = (index: number) => palette[index % palette.length]!;
