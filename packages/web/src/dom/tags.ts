/** What a `feedback()` tag records on its element. `data` runs when a capture is taken. */
export type Tag = { name: string; source?: string; data?: () => unknown };

/** One entry per tagged element, so tagging costs nothing until a capture reads it. */
export const tags = new WeakMap<Element, Tag>();

/** Marks the element that holds the pill and the editor, so a capture leaves Feedback's own UI out. */
export const hostAttribute = 'data-feedback-engine';
