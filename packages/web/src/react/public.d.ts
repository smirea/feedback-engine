/**
 * The types of `@smirea/feedback-engine/react`, written out so an app's compiler never reads the package's source
 * under the app's own options. `public.test.ts` fails the type check when they drift from `index.ts`.
 */

export type FeedbackOptions = {
	/** The app's name in exports. Defaults to the document's title. */
	app?: string;
	version?: string;
	/** The keys that show the Add Feedback pill, such as `Alt+Shift+F`. `false` turns the shortcut off. */
	shortcut?: string | false;
	/** Adds ProcrastiMate to the Share menu. */
	procrastimate?: {
		/** Where ProcrastiMate's API answers: the Vite plugin's proxy path, or a server that allows this origin. */
		url: string;
		/** Sent as a bearer token. Leave it out behind the proxy, which adds its own. */
		token?: string;
		/** The ProcrastiMate web app, for the link to a posted task. */
		app?: string;
	};
};

export type FeedbackEngine = {
	/** Registers app state to attach to every capture. `value` runs when a capture is taken. Registering a name again replaces the earlier one. */
	context(name: string, value: () => unknown): void;
	/** Captures the page and opens the editor. Does nothing while the editor is open. */
	present(): Promise<void>;
	/** Shows the Add Feedback pill, as the shortcut does. */
	showPill(): void;
	/** The files of the last export, for automation that cannot use the clipboard or a download. */
	readonly lastExport: { name: string; blob: Blob }[];
	/** Removes the shortcut and Feedback's UI from the page. */
	destroy(): void;
};

/** A value that Feedback describes as `toFeedback()` in its place, at any depth. */
export type FeedbackRepresentable = { toFeedback(): unknown };

/**
 * Turns Feedback on: the shortcut shows a pill that captures the page and opens the editor. Call it once, in the
 * browser, before or after React renders. On a server it returns an engine that does nothing.
 */
export function setupFeedbackEngine(options?: FeedbackOptions): FeedbackEngine;

type Named = (name: string, data?: () => unknown) => (element: Element | null) => void;

/**
 * Names an element in feedback captures: `<section ref={feedback('Chart', () => plot)}>`. The Vite plugin already
 * finds every component of the app, so this is for a region drawn inline, and for a component's root element, under
 * the component's own name, to report data that React keeps out of its props, such as state. `data` runs when a
 * capture is taken.
 */
export const feedback: Named & {
	/** What the Vite plugin rewrites `feedback(` into. Not for app code. */
	at(source: string): Named;
};

declare global {
	/** The engine of this page, for automation: `__feedbackEngine.present()` and `__feedbackEngine.lastExport`. */
	var __feedbackEngine: FeedbackEngine | undefined;
}
