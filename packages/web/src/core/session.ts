import { Annotations, type FeedbackItem, type Reference } from './annotations.ts';
import { hitTest, pathFrom, similar, type Capture, type Node, type Point } from './model.ts';
import { reportJSON } from './report.ts';

/** Tapping a toast with a link opens it, such as the task a post created. */
export type Toast = { text: string; link?: string };

/** The editor's state and rules, without any drawing. */
export class Session {
	readonly capture: Capture;
	picked = 0;
	/** How far up from the picked node the target sits. 0 is the picked node itself. */
	level = 0;
	/** A new item's text. It survives visits to targets that already have feedback. */
	draft = '';
	/** Unsaved changes to the target's existing feedback, dropped when the target changes. */
	private revision: string | undefined;
	toast: Toast | undefined;
	readonly annotations = new Annotations();
	/** What a tap picks while the text ends in `@`, and how far up from it the reference sits. */
	private referencePick: number | undefined;
	referenceLevel = 0;
	/** The id of every item that was in a completed share. */
	readonly shared = new Set<string>();

	constructor(capture: Capture) {
		this.capture = capture;
	}

	get items() {
		return this.annotations.items;
	}

	/** Closing asks first when it would lose these, or a draft. */
	get unshared() {
		return this.items.filter(item => !this.shared.has(item.id));
	}

	markShared(items: FeedbackItem[]) {
		for (const item of items) this.shared.add(item.id);
	}

	get path() {
		return pathFrom(this.capture, this.picked);
	}

	get target(): Node {
		const path = this.path;
		return path[Math.min(this.level, path.length - 1)]!;
	}

	get similar() {
		return this.target.kind === 'screen' || this.isReferencing ? [] : similar(this.capture, this.target.id);
	}

	/** The item on the target itself. Its parent's or child's feedback belongs to that level. */
	get editing() {
		return this.items.find(item => item.target === this.target.id);
	}

	get text() {
		return this.editing ? (this.revision ?? this.editing.text) : this.draft;
	}

	set text(value: string) {
		if (this.editing) this.revision = value;
		else this.draft = value;
		if (!this.isReferencing) this.referencePick = undefined;
	}

	/** Typing `@` at the start of a word makes the next tap pick a node to reference instead of moving the target. Typing anything else leaves the mode. */
	get isReferencing() {
		const text = this.text;
		return text.endsWith('@') && (text.length === 1 || /\s/.test(text.at(-2)!));
	}

	get referencePath() {
		return this.isReferencing && this.referencePick !== undefined ? pathFrom(this.capture, this.referencePick) : [];
	}

	get referenceTarget(): Node | undefined {
		const path = this.referencePath;
		return path[Math.min(this.referenceLevel, path.length - 1)];
	}

	/** The references the items and the text being typed name, so their boxes show while typing. */
	get visibleReferences(): Reference[] {
		return this.annotations.referencesIn([...this.items.map(item => item.text), this.text]);
	}

	colorIndex(node: number) {
		return this.annotations.colorIndex(node);
	}

	stepReference(level: number) {
		this.referenceLevel = level;
	}

	/** Replaces the `@` with the reference target's token. */
	insertReference() {
		const node = this.referenceTarget;
		if (!node) return;
		this.text = `${this.text.slice(0, -1)}${this.annotations.reference(node).token} `;
	}

	private get trimmed() {
		return this.text.trim();
	}

	get canSubmit() {
		return this.trimmed !== '' && this.trimmed !== this.editing?.text;
	}

	/** Closing would lose a new item's text or changes to an existing one. */
	get isTyping() {
		return this.draft.trim() !== '' || (this.editing !== undefined && this.canSubmit);
	}

	/**
	 * A tap inside an item's box selects that item, so its feedback comes back. Tapping the same spot again drills
	 * down to the most specific node. Screens and layers cover everything, so their feedback never captures a tap.
	 */
	pick(point: Point) {
		const id = hitTest(this.capture, point);
		if (this.isReferencing) {
			this.referencePick = id;
			this.referenceLevel = 0;
			return;
		}
		const flagged = new Set(this.items.map(item => item.target));
		const level = Math.max(
			0,
			pathFrom(this.capture, id).findIndex(
				node => flagged.has(node.id) && node.kind !== 'screen' && node.kind !== 'layer',
			),
		);
		const drillsDown = id === this.picked && this.level === level;
		this.retarget(() => {
			this.picked = id;
			this.level = drillsDown ? 0 : level;
		});
	}

	select(id: number) {
		this.retarget(() => {
			this.picked = id;
			this.level = 0;
		});
	}

	step(level: number) {
		this.retarget(() => {
			this.level = level;
		});
	}

	/** Unsaved changes stay while the same node remains the target, such as a second tap on it. */
	private retarget(change: () => void) {
		const before = this.target.id;
		change();
		if (this.target.id !== before) this.revision = undefined;
		if (!this.isReferencing) this.referencePick = undefined;
	}

	submit() {
		const text = this.trimmed;
		if (!text) return;
		if (!this.editing) this.draft = '';
		this.annotations.submit(text, this.target.id);
		this.select(0);
	}

	remove(id: string) {
		this.annotations.remove(id);
	}

	get json() {
		return reportJSON(this.capture, this.annotations);
	}

	get compactJSON() {
		return reportJSON(this.capture, this.annotations, false);
	}
}
