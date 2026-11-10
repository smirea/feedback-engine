# Web package plan

Feedback gets a web package with the features of the iOS package wherever a browser allows them. It is one npm package, `@smirea/feedback-engine`, with one entry point per framework. Svelte comes first.

```ts
import { setupFeedbackEngine } from '@smirea/feedback-engine/svelte';
```

[`spec/features.md`](../spec/features.md) is the row-by-row parity list. This plan says how the package is shaped, what a spike measured, what does not carry over, and the order of the work. Delete each phase from this file when it lands. The features table is the lasting record.

## The repository is now a Bun workspace beside the Swift package

The layout follows `setup-new-app --type svelte`, changed to fit a library, and it matches `sync-engine`, which already ships Swift and TypeScript from one repository.

| Template piece | Here |
| --- | --- |
| Root `package.json` | Named `@smirea/feedback-engine`. It is the installable package, so `github:smirea/feedback-engine` installs it the way `Package.swift` at the root serves Swift. |
| `apps/ui` | `examples/todo-svelte`, a SvelteKit SPA that mirrors `examples/todo-ios`. It has the Lists screen so far. |
| `apps/server` | Dropped. The package has no server half. |
| `packages/shared` | Dropped. Its only content was the env reader, which is now `examples/todo-svelte/env.ts`. |
| `.env` with env-manager | Kept, with `UI_URL` and `UI_PORT` only. Worktrees get their own port from it. |
| Oxlint, oxfmt, Lefthook, `scripts/test-*.ts` | Kept. Markdown is left out of oxfmt, because it pads these wide tables into unreadable diffs. |
| CI | Kept, with Bun and Swift jobs. The repository had no CI before. |

The web package's source goes in `packages/web/src`. The root `package.json` gains an `exports` map when phase 1 adds the first entry point.

## One package, raw source, one entry point per framework

```
packages/web/src/
  core/     Pure TypeScript. Model, tree building, hit-testing, similar nodes, JSON report, session, card layout, task title, value description.
  dom/      Browser code without a framework. Capture, screenshot, clipboard, share, ProcrastiMate client.
  editor/   The editor and the pill, written in Svelte and mounted in the page's top layer.
  svelte/   The entry point. setupFeedbackEngine, the feedback attachment.
  vite/     The build plugin that writes file:line and the component name into each tag.
```

`core` is the port of the iOS files that already compile on macOS without UIKit (`Model`, `TreeBuilder`, `Report`, `Describer`, `Session`, `TaskTitle`, and `CardLayout`). `Stitch` does not port. The browser renders the whole document in one pass, so there is nothing to stitch.

The package ships TypeScript and Svelte source, as `sync-engine` does, and the app's Vite compiles it. No build step and no npm publish are needed. A consumer installs `github:smirea/feedback-engine` and tracks `master`.

The intended API, next to its iOS counterpart:

| iOS | Web |
| --- | --- |
| `Feedback.enable()` | `const feedback = setupFeedbackEngine({ app, version })` |
| `Feedback.context("Store") { store }` | `feedback.context('Store', () => store)` |
| `Feedback.present()` | `feedback.present()` |
| `.feedback(self)` | `{@attach feedback()}` on the component's root element |
| `.feedback("Chart", data: plot)` | `{@attach feedback('Chart', () => plot)}` |
| `#fileID`, `#line` | `feedbackEngine()` from `@smirea/feedback-engine/vite`, added to the Svelte preprocessors |

A React entry point would reuse `core` and `dom` and add its own tag API. The editor is the open part. A React app does not compile Svelte files, so a React entry point needs the editor as a compiled bundle, which a raw-source GitHub install does not provide. Decide that when a React app needs Feedback.

## What a spike measured

A throwaway package and a copy of `examples/todo-svelte` ran under Playwright 1.64.1 in Chromium and WebKit, in a Vite dev server and in a production build. Versions were Svelte 5.57.3, SvelteKit 3.2.0, and Vite 8.3.7. The package was installed from a packed tarball, so it sat in `node_modules` as a GitHub install would. The spike code was not kept. Phase 2 turns the same checks into tests.

| Question | Result |
| --- | --- |
| Does a raw-source package with `.ts`, `.svelte`, and `.svelte.ts` files work from `node_modules`? | Yes, in dev and in the production build, in both browsers. A pill component with rune state mounted from the package with no page errors. |
| Can a tag know its `file:line`? | Yes. A Svelte preprocessor rewrote each `{@attach feedback(` call, and all 9 tagged components reported locations such as `src/lib/ListRow.svelte:8` in dev and in production. |
| Can untagged elements know their `file:line`? | In dev only. Svelte's `__svelte_meta` gave all 26 elements a location in the dev server and none in the production build. |
| Can the DOM stand in for the accessibility tree? | Yes. `dom-accessibility-api` 0.7.1 returned a role and a name for each element, such as `button "New List"` and `textbox "Name"`. Collecting 9 components and 26 elements took 1 to 2 ms. |
| Can a page take its own screenshot? | Yes, for an ordinary page. `modern-screenshot` 4.7.0 rendered the whole 390 by 511 point document from a 420 point viewport in 44 to 66 ms. Against Playwright's own full-page screenshot, 0 of 797,160 pixels differed in Chromium and 0.2% in WebKit. |
| Does the screenshot hold with a modal dialog open? | Partly. The dialog rendered in place, but its `::backdrop` dimming was missing and the input's placeholder was drawn in the text color. |
| Is a modal dialog a separate layer? | Yes. `dialog[open]` gave a second layer with its 6 elements. |
| Can a page write the export to the clipboard? | Yes, with one limit. Chromium accepted one clipboard item with a PNG, and one item with a PNG and plain text. It refused two items with `Support for multiple ClipboardItems is not implemented`. WebKit was not measured, because Playwright cannot grant it clipboard access. |
| Is there an on-device model? | Unproven. `LanguageModel` and `Summarizer` exist on `window` in Playwright's Chromium. Whether a model is available was not tested. |

## What works, what changes, and what does not

**Carries over unchanged.** The export format, the tree rules, hit-testing, similar nodes, the session rules of the editor, `@` references, the image layout, the task name, `taps.py`, and the limits on component data. These are pure logic, and the TypeScript core ports them against the same expected values as the Swift tests.

**Works better on the web.**

- A capture needs no scrolling and no stitching. The scroll-step reader, the cover window, and `Stitch` have no web counterpart.
- The DOM gives the real hierarchy. iOS reads tags and accessibility elements from two sources and joins them by geometry. The web reads one tree, so an element's parent and a component inside a button are known, not inferred.
- The DOM always carries roles and names. The private accessibility switch and its first-capture pause of about a second have no web counterpart.
- In development builds every element knows its own `file:line`, so an item on an untagged button can name the line of that button.
- The Vite plugin sees every component file, so it can name a tag after its file, as `.feedback(self)` names it after its type.

**Changes shape.**

- The trigger is a keyboard shortcut on a desktop. A shake works only on phones, and iOS Safari asks for permission first.
- `file:line` comes from a build plugin, so an app adds one line to its Vite config.
- Component data is explicit at first. Svelte has no reflection over a component. The plugin may be able to pass the declared props, which is unproven.
- Values in component data are JavaScript values, so `report.md` needs rules for `null`, `undefined`, plain objects, and class instances.
- **Copy Feedback** for the ZIP writes one clipboard item with two representations, not two items.
- Sharing uses `navigator.share` where the browser has it and a download elsewhere.

**Does not work today.**

- **ProcrastiMate from a browser.** The iOS package reads ProcrastiMate's session from a shared keychain group. A browser has no such store, and ProcrastiMate's API sends no CORS headers (`server/src` has no `Access-Control` header), so a page on another origin cannot call it at all. See the decisions below.
- **Screenshot fidelity for everything a browser can draw.** The render is a re-draw of the DOM, not a read of the pixels. Dialog backdrops are missing, as measured. Cross-origin images, `<canvas>`, `<video>`, and iframes are known weak spots of this method and were not measured.
- **The keyboard block, the expanded-sheet capture, and the Dynamic Island morph.** These are iOS-only by nature.

## Decisions that are yours

Each has a default that the work proceeds on until you say otherwise.

1. **The shortcut.** Default: `Alt+Shift+F`, configurable in `setupFeedbackEngine`, with shake on phones behind a one-time permission tap. You could instead pick another combination, or require every app to wire its own button to `present()`.
2. **ProcrastiMate on the web.** Default: ProcrastiMate's API allows cross-origin calls that carry a bearer token, and the app passes a token to `setupFeedbackEngine`. This needs a change in the ProcrastiMate server and puts a token in the page, so it suits development builds only. You could instead have each app proxy the post through its own server, which keeps the token off the page and needs a server in every app, or leave ProcrastiMate out of the web package.
3. **Notation of component data.** Default: the same structure with JavaScript literals, so `Entry(kg: 72.575, note: nil)` on iOS and `{kg: 72.575, note: null}` on the web. You could instead force the Swift spelling on both, which keeps one notation and reads oddly beside JavaScript source.

## Phases

Each phase is one PR and ends in a check that runs in CI. The example app grows a screen whenever a phase needs one.

1. **Core in TypeScript, checked against iOS.** Port the pure core to `packages/web/src/core`. Move the expected values that define the contract (raw scene to nodes, hit tests, similar nodes, report JSON, described values) into `spec/fixtures` as JSON that both `swift test` and `bun test` read. Update `report.md` for JavaScript values and for hierarchy over geometry. Check: both test suites pass on the same fixtures, and changing a fixture fails both.
2. **Capture.** `dom` collects tags, elements, layers, the environment, and the screenshot. `svelte` adds `setupFeedbackEngine`, `context`, and the `feedback` attachment. `vite` adds locations and names. Check: a Playwright test captures the example app and compares `feedback.json` with an expected tree, in dev and in a production build, in Chromium and WebKit. `taps.py` runs on that export.
3. **Editor.** The pill, the shortcut, and the editor in the top layer, driven by the ported `Session`. Check: a Playwright test follows the steps of the README's "Give feedback" section, at desktop and phone widths.
4. **Export and sharing.** The image export on a canvas, the ZIP, the clipboard, share, and download. Check: the exported PNG has the expected size and boxes, and Playwright reads the clipboard back.
5. **ProcrastiMate.** After decision 2. Check: a post against a scratch ProcrastiMate server creates a task with both attachments.
6. **Skill and docs.** `skills/feedback-accessibility` gains a Svelte section, the README gains a Web section, and `examples/todo-svelte` reaches the screens of `examples/todo-ios`. Check: the skill's verify steps pass on every example screen.

## Risks

- **Real Safari.** Playwright's WebKit is not Safari. Libraries that use this screenshot method document first-render gaps for images and fonts in Safari, which the spike did not test. Phase 2 needs one run on a real iPhone, which is a manual check.
- **Canvas size.** iOS Safari limits a canvas to about 16.7 million pixels, a published browser limit that the spike did not test. A 390 point wide page at 3x passes it at roughly 4,700 points tall, so the height limit of C6 is lower on phones than in the iOS package.
- **Fixed and sticky bars.** A full-length render draws a `position: fixed` bar once. Its frame in the tree has to move with it. Phase 2 needs a test page with a fixed header and a fixed footer.
- **Style isolation.** The editor must not inherit the app's CSS, and the capture must not include the editor. A shadow root is the usual answer, and Svelte's handling of component styles inside one is unproven here. Phase 3 starts with that prototype.
- **Svelte version.** Attachments need Svelte 5.29 or later. An app on an older Svelte 5 needs the `use:` form or an upgrade.
- **Dev-only locations.** G10 relies on `__svelte_meta`, which is internal to Svelte. If Svelte renames it, untagged elements lose their locations and tagged components keep theirs.
