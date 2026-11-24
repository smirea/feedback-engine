/**
 * The types of `@stefan.inc/feedback-engine/react`, written out so an app's compiler never reads the package's source
 * under the app's own options. `packages/web/public-types.check.ts` fails the type check when they drift from `index.ts`.
 */

export type FeedbackOptions = {
  /** The app's name in exports. Defaults to the document's title. */
  app?: string;
  version?: string;
  /**
   * Lines the image export prints under its title, as `label: value`, such as `{ 'Signed in': 'ana@example.com' }`.
   * They are the first entries of the JSON export's `environment` after `App`. Runs when a capture is taken.
   */
  metadata?: () => Record<string, string>;
  /**
   * The app's own files, such as its saved state, in every export but the image: the Data export, the ZIP, ProcrastiMate,
   * and webhooks. Each `data` runs when a capture is taken, so the files match the screenshot.
   */
  files?: FeedbackFile[];
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
   * Holding three fingers still on the screen for a moment captures the page, for a phone, which has no keyboard. A
   * capsule grows at the top center while the fingers are down. On unless `false`.
   */
  threeFingerHold?: boolean;
  /**
   * Adds ProcrastiMate to the Share menu. Pass `{ projects: ['Website'] }` to post through a popup on the
   * ProcrastiMate web app (`/feedback`) using whoever is signed in there, with no token and no proxy.
   */
  procrastimate?: {
    /** The ProcrastiMate web app whose `/feedback` popup opens. Defaults to `https://procrastimate.stf.lol`. */
    app?: string;
    /** The project the picker opens on, by name (ignoring case) or id, in place of the last one posted to. */
    project?: string;
    /**
     * The only projects the `/feedback` popup offers, by name (ignoring case) or id, in this order. The Inbox is not
     * offered. Required, and not empty.
     */
    projects: string[];
    /**
     * Another user's space (their ProcrastiMate user id) whose shared projects the popup lists. Leave it out to match
     * across the signed-in user's own and edit-shared projects.
     */
    space?: string;
  };
  /**
   * Adds one entry to the Share menu per webhook. Choosing it posts the image export, the JSON export, and the app's
   * `files` to the webhook's `url`, with nothing more to fill in. The menu lists ProcrastiMate, then the webhooks with
   * `githubIcon`, then the others.
   */
  webhooks?: Webhook[];
  /**
   * The destinations that get a button beside Share instead of an entry in its menu, by name, in this order:
   * `'ProcrastiMate'` or a webhook's `name`. A name with no destination is skipped. Without it, the first two of
   * ProcrastiMate and the webhooks get one. `[]` gives none.
   */
  pinned?: string[];
};

/** A file the app adds to every export, made when a capture is taken. */
export type FeedbackFile = {
  /** The file's name in every export, such as `save.json`. */
  name: string;
  /**
   * Makes the file when a capture is taken, so it matches the screenshot. A `Blob` is used as it is, a string as text,
   * and anything else as JSON. `null` or `undefined` leaves the file out, for a screen that has nothing to put in it.
   */
  data: () => unknown;
  /** The media type. Without it, a `Blob` keeps its own, `.json` is `application/json`, and other text is `text/plain`. */
  type?: string;
};

/** One entry of the Share menu that posts the feedback to a server of the app's own. `docs/webhooks.md` has the request. */
export type Webhook = {
  /** The entry's name in the Share menu, such as `GitHub Issue`. */
  name: string;
  /** Where the post goes. A path, such as `/api/feedback`, is on the page's own origin. */
  url: string;
  /** An icon beside the name: anything an `<img>` loads, such as `githubIcon` or a data URL. */
  image?: string;
  /** Sent with the post, such as `Authorization`. Whatever a page sends is public. */
  headers?: WebhookValues;
  /** Added to the URL's query. */
  query?: WebhookValues;
};

/**
 * Fixed values, or a function that runs for every post and again on a retry, so it can read what did not exist when
 * the app started, such as the token of a user who signed in since. What it throws is shown as the post's failure.
 */
export type WebhookValues =
  | Record<string, string>
  | (() => Record<string, string> | Promise<Record<string, string>>);

/** GitHub's mark in white, for a webhook that files issues. */
export const githubIcon: string;

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
  /**
   * Reads the page as it is now and returns its JSON export, with no items, without drawing it or opening the editor.
   * For agents and scripts that check a screen: `await page.evaluate(() => __feedbackEngine.capture())`.
   */
  capture(): Promise<FeedbackReport>;
  /** The files of the last export, for automation that cannot use the clipboard or a download. */
  readonly lastExport: { name: string; blob: Blob }[];
  /** Removes the shortcut and Feedback's UI from the page. */
  destroy(): void;
};

type Rect = { x: number; y: number; width: number; height: number };
type Pointer = { target: number; title: string; path: number[]; code?: string };

/** The JSON export, as `spec/report.md` defines it. */
export type FeedbackReport = {
  app: string;
  captured: string;
  size: { width: number; height: number };
  visible: Rect;
  environment: { name: string; value: string }[];
  items: (Pointer & { number: number; text: string })[];
  references: (Pointer & { number: number; token: string })[];
  context: { name: string; value: string }[];
  nodes: {
    id: number;
    parent?: number;
    layer: number;
    kind: "screen" | "layer" | "component" | "element";
    name: string;
    label?: string;
    frame: Rect;
    source?: string;
    data?: string;
  }[];
};

/** A value that Feedback describes as `toFeedback()` in its place, at any depth. */
export type FeedbackRepresentable = { toFeedback(): unknown };

/**
 * Turns Feedback on: Alt+Meta+click on anything captures the page and opens the editor on what was clicked, and so
 * does a three-finger hold on a phone. Call it once, in the browser, before or after React renders. On a server it
 * returns an engine that does nothing.
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
  /** The engine of this page, for automation: `__feedbackEngine.present()`, `__feedbackEngine.capture()`, and `__feedbackEngine.lastExport`. */
  var __feedbackEngine: FeedbackEngine | undefined;
}
