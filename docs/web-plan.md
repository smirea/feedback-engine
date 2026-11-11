# Web package: what is left

The web package, `@smirea/feedback-engine`, is in `packages/web/src` and on par with the iOS package wherever a browser allows it. [`spec/features.md`](../spec/features.md) is the row-by-row record. This file lists the rows that are still `planned` for the web, and the risks that tests do not cover. Delete an item when it lands.

## Planned

- **A shake on phones (T8).** It needs the `devicemotion` permission, which iOS Safari grants only from a tap, and a physical phone to check it on. Until then a phone opens the editor from the app's own control.
- **A task name from an on-device model (P5).** Chrome has a built-in model behind `LanguageModel`. On the machine this was developed on, Chrome 156 reported it as `unavailable`, so the code could not be checked and was not written. `taskTitle` in the core already has the prompt and the cleanup of the reply.
- **A container that reports its caller's location (G4).** The Vite plugin would have to pass the `file:line` of each `<Legend />` to the component.
- **A React entry point.** It would reuse `core` and `dom` and add its own tag API. The editor is the open part. A React app does not compile Svelte files, so a React entry point needs the editor as a compiled bundle, which a source-only GitHub install does not provide. Decide that when a React app needs Feedback.

## Decisions taken, which you can change

- **The shortcut** is `Alt+Shift+F`, and `setupFeedbackEngine({ shortcut })` changes it.
- **ProcrastiMate** goes through the dev server. `feedbackProcrastimate()` forwards the page's calls and adds a token from the server's environment. This replaced the first plan, a CORS change in ProcrastiMate with a token in the page, because it needs no change and no deploy in ProcrastiMate and keeps the token off the page. A deployed static site has no ProcrastiMate entry. If a deployed app needs one, ProcrastiMate has to allow that origin, and the app passes `procrastimate: { url, token }`, which the client already takes.
- **Component data** is written with JavaScript literals, such as `{kg: 72.575, note: null}`.

## Risks that tests do not cover

- **Real Safari.** The browser tests run Chromium and Playwright's WebKit. Libraries that draw the DOM into a canvas document first-render gaps for images and fonts in Safari. Check one capture on a real iPhone.
- **Cross-origin images, `<canvas>`, `<video>`, and iframes.** The example app has none, so the screenshot of a page that has them is untested.
- **A touch-screen pinch and the share sheet.** Both are written. Playwright can neither pinch nor share.
- **`__svelte_meta`.** Element locations in development builds read a field that is internal to Svelte. If Svelte renames it, untagged elements lose their locations and tagged components keep theirs.
