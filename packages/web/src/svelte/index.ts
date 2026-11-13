import type { Attachment } from 'svelte/attachments';
import { tags } from '../dom/tags.ts';

export type { FeedbackRepresentable } from '../core/index.ts';
export { githubIcon, type Webhook } from '../dom/webhook.ts';
export type { FeedbackOptions } from '../editor/engine.ts';
export { setupFeedbackEngine, type FeedbackEngine } from '../editor/setup.ts';

type Named = (name?: string, data?: () => unknown) => Attachment<Element>;

function tagged(defaults: { name?: string; source?: string; data?: () => unknown }): Named {
	return (name, data) => element => {
		tags.set(element, {
			name: name ?? defaults.name ?? 'Component',
			data: data ?? defaults.data,
			source: defaults.source,
		});
		return () => tags.delete(element);
	};
}

/**
 * Names an element in feedback captures: `{@attach feedback()}` on a component's root element. `data` runs when a
 * capture is taken. The Vite plugin fills in the name, from the file, and the `file:line` of the call. A call without
 * arguments also reports the component's props and state.
 */
export const feedback: Named & {
	/** What the Vite plugin rewrites `feedback(` into. Not for app code. */
	at(source: string, name: string, data?: () => unknown): Named;
} = Object.assign(tagged({}), {
	at: (source: string, name: string, data?: () => unknown) => tagged({ source, name, data }),
});
