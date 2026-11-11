import { mount, unmount } from 'svelte';
import { hostAttribute } from '../dom/tags.ts';
import { defaultShortcut, Engine, matchesShortcut, type FeedbackOptions } from './engine.ts';
import Host from './Host.svelte';

export type FeedbackEngine = {
	/** Registers app state to attach to every capture. `value` runs when a capture is taken. Registering a name again replaces the earlier one. */
	context(name: string, value: () => unknown): void;
	/** Captures the page and opens the editor. Does nothing while the editor is open. */
	present(): Promise<void>;
	/** Shows the Add Feedback pill, as a keyboard shortcut does. Pressing it captures the page. Left alone, it leaves after 5 seconds. */
	showPill(): void;
	/**
	 * Shows the pill counting down from `seconds`, 5 unless given, then captures the page and opens the editor. For a
	 * trigger inside one of the app's menus, such as on a phone: the user has the countdown to leave the menu and reach
	 * the screen they mean. Pressing the pill captures at once.
	 */
	countdown(seconds?: number): void;
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
 * Turns Feedback on: Alt+Meta+click on anything captures the page and opens the editor on what was clicked. Call it
 * once, in the browser. On a server it returns an engine that does nothing, so a layout can call it without a guard.
 */
export function setupFeedbackEngine(options: FeedbackOptions = {}): FeedbackEngine {
	if (typeof document === 'undefined') {
		return { context() {}, present: async () => {}, showPill() {}, countdown() {}, lastExport: [], destroy() {} };
	}
	current?.destroy();

	// Written by `feedbackProcrastimate()` when it has a token. Vite replaces the whole member expression, so it stays in
	// one piece. Webpack has no `import.meta.env`. The cast needs no `import.meta.env` type from the app.
	type Meta = { env?: Record<string, string | undefined> };
	const proxy = (import.meta as Meta).env && (import.meta as Meta).env!.FEEDBACK_PROCRASTIMATE;
	const engine = new Engine({
		...options,
		procrastimate: options.procrastimate ?? (proxy ? { url: proxy } : undefined),
	});
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
	const pointerEvents = ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'] as const;
	const pointer = (event: MouseEvent) => {
		if (!shortcut || !matchesShortcut(shortcut, event) || event.composedPath().includes(host)) return;
		// The click is for Feedback, so the app must not act on it, move focus, or start a text selection.
		event.preventDefault();
		event.stopImmediatePropagation();
		// A disabled control sends pointer events and no click, and a person still points at it.
		if (event.type === 'pointerup') void engine.present({ x: event.clientX, y: event.clientY });
	};
	const hidden = () => {
		if (document.visibilityState === 'hidden') engine.hidePill();
	};
	addEventListener('keydown', keydown);
	// In the capture phase, so the chord reaches Feedback before the element under the pointer.
	for (const type of pointerEvents) addEventListener(type, pointer, true);
	document.addEventListener('visibilitychange', hidden);

	const api: FeedbackEngine = {
		context(name, value) {
			const index = engine.providers.findIndex(provider => provider.name === name);
			if (index !== -1) engine.providers.splice(index, 1);
			engine.providers.push({ name, value });
		},
		present: () => engine.present(),
		showPill: () => engine.showPill(),
		countdown: (seconds = 5) => engine.countdown(seconds),
		get lastExport() {
			return engine.lastExport;
		},
		destroy() {
			removeEventListener('keydown', keydown);
			for (const type of pointerEvents) removeEventListener(type, pointer, true);
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
