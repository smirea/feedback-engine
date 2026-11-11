import { tick } from 'svelte';
import type { Point } from '../core/index.ts';
import { captureScreen, type Screen } from '../dom/capture.ts';
import type { ProcrastimateConfig } from '../dom/procrastimate.ts';
import { hostAttribute } from '../dom/tags.ts';

export type FeedbackOptions = {
	/** The app's name in exports. Defaults to the document's title. */
	app?: string;
	version?: string;
	/**
	 * What opens Feedback. A chord that ends in `Click`, such as the default `Alt+Meta+Click`, opens the editor with the
	 * element under the pointer selected. A chord that ends in a key, such as `Alt+Shift+F`, shows the Add Feedback
	 * pill. `false` turns it off.
	 */
	shortcut?: string | false;
	/**
	 * Shows a round Feedback button on every screen, for a phone or an app opened from the home screen, which have no
	 * keyboard. Pressing it captures the page. Drag it to move it to another height or the other side.
	 */
	button?: boolean;
	/**
	 * Adds ProcrastiMate to the Share menu. Leave it out behind `feedbackProcrastimate()` from the Vite entry point,
	 * which adds the entry by itself when it has a token. Set it for a proxy of your own.
	 */
	procrastimate?: ProcrastimateConfig;
};

export const defaultShortcut = 'Alt+Meta+Click';
const pillSeconds = 5;

/**
 * What the pill and the editor show. One per page. It is plain TypeScript, not a `.svelte.ts` module with runes: Vite
 * pre-bundles a package from `node_modules`, and that step compiles such a module without removing its types.
 */
export class Engine {
	readonly options: FeedbackOptions;
	readonly providers: { name: string; value: () => unknown }[] = [];
	pill = false;
	/** The seconds left before the pill captures by itself, while a countdown runs. */
	remaining: number | undefined;
	screen: Screen | undefined;
	/** Where the user pointed to open the editor, in the capture's coordinates. The editor starts with that node selected. */
	pointed: Point | undefined;
	/** Called after `pill`, `remaining`, or `screen` changes, so the host draws again. */
	onchange = () => {};
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
		this.remaining = undefined;
		this.onchange();
		clearTimeout(this.timer);
		this.timer = setTimeout(() => this.hidePill(), pillSeconds * 1000);
	}

	/**
	 * Shows the pill counting down, then captures. For a trigger inside a menu, which would otherwise capture the menu:
	 * the user has the countdown to reach the screen they mean. Pressing the pill captures at once.
	 */
	countdown(seconds: number) {
		if (this.screen || this.capturing) return;
		this.remember();
		this.pill = true;
		this.remaining = seconds;
		this.onchange();
		clearTimeout(this.timer);
		const count = () => {
			this.remaining! -= 1;
			if (this.remaining! <= 0) return void this.present();
			this.onchange();
			this.timer = setTimeout(count, 1000);
		};
		this.timer = setTimeout(count, 1000);
	}

	hidePill() {
		clearTimeout(this.timer);
		this.pill = false;
		this.remaining = undefined;
		this.onchange();
	}

	/** Captures the page and opens the editor. Does nothing while the editor is open. `at` is where the user pointed, in the window. */
	async present(at?: Point) {
		if (this.screen || this.capturing) return;
		this.remember();
		this.hidePill();
		this.capturing = true;
		this.pointed = at && { x: at.x + scrollX, y: at.y + scrollY };
		try {
			this.screen = await captureScreen({
				app: this.options.app,
				version: this.options.version,
				context: this.providers,
			});
			this.onchange();
		} finally {
			this.capturing = false;
		}
	}

	close() {
		const { focused } = this;
		this.screen = undefined;
		this.onchange();
		this.focused = null;
		// The page stays inert until the editor's modal dialog is gone, and an inert element cannot take focus.
		void tick().then(() => (focused instanceof HTMLElement && focused.isConnected ? focused.focus() : undefined));
	}

	private remember() {
		const active = document.activeElement;
		if (active && !active.hasAttribute(hostAttribute)) this.focused = active;
	}
}

/**
 * Whether an event is the shortcut: a click of the main button for a chord that ends in `Click`, a key press for any
 * other. Letters match by physical key, since Alt changes the character a Mac types.
 */
export function matchesShortcut(shortcut: string, event: KeyboardEvent | MouseEvent) {
	const keys = shortcut.split('+').map(key => key.trim().toLowerCase());
	const key = keys.pop()!;
	const modifiers = { alt: event.altKey, shift: event.shiftKey, ctrl: event.ctrlKey, meta: event.metaKey };
	const wanted = new Set(
		keys.map(name =>
			name === 'cmd' || name === 'command' ? 'meta' : name === 'control' ? 'ctrl' : name === 'option' ? 'alt' : name,
		),
	);
	if (Object.entries(modifiers).some(([name, pressed]) => pressed !== wanted.has(name))) return false;
	if (key === 'click') return 'button' in event && event.button === 0;
	if (!('code' in event)) return false;
	const code = /^[a-z]$/.test(key) ? `Key${key.toUpperCase()}` : /^\d$/.test(key) ? `Digit${key}` : undefined;
	return code ? event.code === code : event.key.toLowerCase() === key;
}
