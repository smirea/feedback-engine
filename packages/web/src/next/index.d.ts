/**
 * Adds Feedback to a Next.js config, for Turbopack and for webpack: it registers the app's components for captures,
 * compiles the editor, and writes each HTML element's `file:line` into a `data-feedback-source` attribute.
 */
export function withFeedbackEngine<Config extends object>(
	config?: Config,
	options?: {
		/** Writes each HTML element's `file:line` into the page. Defaults to `next dev` only. Set it for a deployed preview. */
		elementSources?: boolean;
		/** The folder paths are written from. Defaults to the working directory. */
		root?: string;
	},
): Config;
