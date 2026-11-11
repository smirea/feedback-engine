import { mount, unmount } from 'svelte';
import type { Attachment } from 'svelte/attachments';
import { hostAttribute, tags } from '../dom/tags.ts';
import { defaultShortcut, Engine, matchesShortcut, type FeedbackOptions } from '../editor/engine.svelte.ts';
import Host from '../editor/Host.svelte';

export type { FeedbackOptions } from '../editor/engine.svelte.ts';
export type { FeedbackRepresentable } from '../core/index.ts';

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

declare global {
	/** The engine of this page, for automation: `__feedbackEngine.present()` and `__feedbackEngine.lastExport`. */
	var __feedbackEngine: FeedbackEngine | undefined;
}

let current: { engine: FeedbackEngine; destroy: () => void } | undefined;

/**
 * Turns Feedback on: the shortcut shows a pill that captures the page and opens the editor. Call it once, in the
 * browser. On a server it returns an engine that does nothing, so a layout can call it without a guard.
 */
export function setupFeedbackEngine(options: FeedbackOptions = {}): FeedbackEngine {
	if (typeof document === 'undefined') {
		return { context() {}, present: async () => {}, showPill() {}, lastExport: [], destroy() {} };
	}
	current?.destroy();

	const engine = new Engine(options);
	const host = document.createElement('div');
	host.setAttribute(hostAttribute, '');
	// The shadow root keeps the app's styles out of the editor and the editor's styles out of the app.
	const root = host.attachShadow({ mode: 'open' });
	document.documentElement.append(host);
	const component = mount(Host, { target: root, props: { engine } });

	const shortcut = options.shortcut ?? defaultShortcut;
	const keydown = (event: KeyboardEvent) => {
		if (shortcut && matchesShortcut(shortcut, event)) {
			event.preventDefault();
			engine.showPill();
		}
	};
	const hidden = () => {
		if (document.visibilityState === 'hidden') engine.hidePill();
	};
	addEventListener('keydown', keydown);
	document.addEventListener('visibilitychange', hidden);

	const api: FeedbackEngine = {
		context(name, value) {
			const index = engine.providers.findIndex(provider => provider.name === name);
			if (index !== -1) engine.providers.splice(index, 1);
			engine.providers.push({ name, value });
		},
		present: () => engine.present(),
		showPill: () => engine.showPill(),
		get lastExport() {
			return engine.lastExport;
		},
		destroy() {
			removeEventListener('keydown', keydown);
			document.removeEventListener('visibilitychange', hidden);
			void unmount(component);
			host.remove();
			if (current?.engine === api) current = undefined;
			globalThis.__feedbackEngine = undefined;
		},
	};
	current = { engine: api, destroy: api.destroy };
	globalThis.__feedbackEngine = api;
	return api;
}

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
