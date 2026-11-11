import { tick } from 'svelte';
import { captureScreen, type Screen } from '../dom/capture.ts';
import type { ProcrastimateConfig } from '../dom/procrastimate.ts';
import { hostAttribute } from '../dom/tags.ts';

export type FeedbackOptions = {
	/** The app's name in exports. Defaults to the document's title. */
	app?: string;
	version?: string;
	/** The keys that show the Add Feedback pill, such as `Alt+Shift+F`. `false` turns the shortcut off. */
	shortcut?: string | false;
	/** Adds ProcrastiMate to the Share menu. */
	procrastimate?: ProcrastimateConfig;
};

export const defaultShortcut = 'Alt+Shift+F';
const pillSeconds = 5;

/** What the pill and the editor show. One per page. */
export class Engine {
	readonly options: FeedbackOptions;
	readonly providers: { name: string; value: () => unknown }[] = [];
	pill = $state(false);
	screen = $state.raw<Screen | undefined>(undefined);
	/** The files of the last export, for automation that cannot use the clipboard or a download. */
	lastExport: { name: string; blob: Blob }[] = [];
	private capturing = false;
	/** What had focus before the pill or the editor took it, to give it back on close. */
	private focused: Element | null = null;
	private timer: ReturnType<typeof setTimeout> | undefined;

	constructor(options: FeedbackOptions) {
		this.options = options;
	}

	/** Shows the pill. Left alone, it leaves after five seconds, so an accidental trigger costs nothing. Triggering again restarts the timer. */
	showPill() {
		if (this.screen || this.capturing) return;
		this.remember();
		this.pill = true;
		clearTimeout(this.timer);
		this.timer = setTimeout(() => this.hidePill(), pillSeconds * 1000);
	}

	hidePill() {
		clearTimeout(this.timer);
		this.pill = false;
	}

	/** Captures the page and opens the editor. Does nothing while the editor is open. */
	async present() {
		if (this.screen || this.capturing) return;
		this.remember();
		this.hidePill();
		this.capturing = true;
		try {
			this.screen = await captureScreen({
				app: this.options.app,
				version: this.options.version,
				context: this.providers,
			});
		} finally {
			this.capturing = false;
		}
	}

	close() {
		const { focused } = this;
		this.screen = undefined;
		this.focused = null;
		// The page stays inert until the editor's modal dialog is gone, and an inert element cannot take focus.
		void tick().then(() => (focused instanceof HTMLElement && focused.isConnected ? focused.focus() : undefined));
	}

	private remember() {
		const active = document.activeElement;
		if (active && !active.hasAttribute(hostAttribute)) this.focused = active;
	}
}

/** Whether a key event is the shortcut. Letters match by physical key, since Alt changes the character a Mac types. */
export function matchesShortcut(shortcut: string, event: KeyboardEvent) {
	const keys = shortcut.split('+').map(key => key.trim().toLowerCase());
	const key = keys.pop()!;
	const modifiers = { alt: event.altKey, shift: event.shiftKey, ctrl: event.ctrlKey, meta: event.metaKey };
	const wanted = new Set(
		keys.map(name =>
			name === 'cmd' || name === 'command' ? 'meta' : name === 'control' ? 'ctrl' : name === 'option' ? 'alt' : name,
		),
	);
	if (Object.entries(modifiers).some(([name, pressed]) => pressed !== wanted.has(name))) return false;
	const code = /^[a-z]$/.test(key) ? `Key${key.toUpperCase()}` : /^\d$/.test(key) ? `Digit${key}` : undefined;
	return code ? event.code === code : event.key.toLowerCase() === key;
}
