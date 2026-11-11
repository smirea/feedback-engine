import type { Plugin } from 'vite';

/** The name a tag gets without one, from the component's file. */
export function componentName(file: string): string;

/** Rewrites each `{@attach feedback(...)}` call so it carries its `file:line` and a default name. `undefined` when nothing changed. */
export function addLocations(content: string, file: string): string | undefined;

/** A Svelte preprocessor that gives every `feedback()` tag its `file:line` and a default name. */
export function feedbackEngine(options?: {
	/** The folder paths are written from. Defaults to the working directory. */
	root?: string;
}): { name: string; markup(input: { content: string; filename?: string }): { code: string } | undefined };

/** A Vite plugin that forwards `path` on the dev and preview servers to ProcrastiMate and adds the token there. */
export function feedbackProcrastimate(options?: {
	/** ProcrastiMate's origin. Defaults to `https://procrastimate.stf.lol`. */
	url?: string;
	token?: string;
	/** Defaults to `/__feedback/procrastimate`. */
	path?: string;
}): Plugin;
