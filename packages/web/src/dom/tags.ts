/** What a `feedback()` tag records on its element. `data` runs when a capture is taken. */
export type Tag = { name: string; source?: string; data?: () => unknown };

/** One entry per tagged element, so tagging costs nothing until a capture reads it. */
export const tags = new WeakMap<Element, Tag>();

/** A component a framework knows without a tag, and the elements it draws. Several, when it renders siblings. */
export type Component = { tag: Tag; roots: Element[] };

/**
 * How a capture finds components without tags. An entry point sets `read` when its framework keeps a component tree
 * at runtime, as React does. It runs once per capture and gives, for each element, the components that element is a
 * root of, outermost first.
 */
export const discovery: { read?: () => Map<Element, Component[]> } = {};

/** Marks the element that holds the pill and the editor, so a capture leaves Feedback's own UI out. */
export const hostAttribute = 'data-feedback-engine';

/** An element's `file:line`, written by a build plugin for a framework that does not record one itself. */
export const sourceAttribute = 'data-feedback-source';
