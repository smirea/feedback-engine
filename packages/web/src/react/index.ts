import { discovery, tags } from '../dom/tags.ts';
import type { FeedbackOptions } from '../editor/engine.ts';
import { setupFeedbackEngine as setup, type FeedbackEngine } from '../editor/setup.ts';
import { readComponents } from './components.ts';

export type { FeedbackRepresentable } from '../core/index.ts';
export { githubIcon, type Webhook, type WebhookValues } from '../dom/webhook.ts';
export type { FeedbackOptions } from '../editor/engine.ts';
export type { FeedbackEngine } from '../editor/setup.ts';

/**
 * Turns Feedback on: Alt+Meta+click on anything captures the page and opens the editor on what was clicked. Call it
 * once, in the browser, before or after React renders. On a server it returns an engine that does nothing.
 */
export function setupFeedbackEngine(options: FeedbackOptions = {}): FeedbackEngine {
	discovery.read = readComponents;
	return setup(options);
}

type Ref = (element: Element | null) => void;
type Named = (name: string, data?: () => unknown) => Ref;

function tagged(source?: string): Named {
	return (name, data) => {
		let current: Element | undefined;
		// React calls a ref with the element when it mounts and with `null` when it unmounts, and does both again on every render that passes a new function.
		return element => {
			if (current) tags.delete(current);
			current = element ?? undefined;
			if (element) tags.set(element, { name, data, source });
		};
	};
}

/**
 * Names an element in feedback captures: `<section ref={feedback('Chart', () => plot)}>`. The Vite plugin already
 * finds every component of the app, so this is for a region drawn inline, and for a component's root element, under
 * the component's own name, to report data that React keeps out of its props, such as state. `data` runs when a
 * capture is taken.
 */
export const feedback: Named & {
	/** What the Vite plugin rewrites `feedback(` into. Not for app code. */
	at(source: string): Named;
} = Object.assign(tagged(), { at: (source: string) => tagged(source) });
