# Web package: what is left

The web package, `@smirea/feedback-engine`, is in `packages/web/src` and on par with the iOS package wherever a browser allows it. [`spec/features.md`](../spec/features.md) is the row-by-row record. This file lists the rows that are still `planned` for the web, and the risks that tests do not cover. Delete an item when it lands.

## Planned

- **A shake on phones (T8).** It needs the `devicemotion` permission, which iOS Safari grants only from a tap, and a physical phone to check it on. Until then a phone starts a countdown from one of the app's menus.
- **A task name from an on-device model (P5).** Chrome has a built-in model behind `LanguageModel`. On the machine this was developed on, Chrome 156 reported it as `unavailable`, so the code could not be checked and was not written. `taskTitle` in the core already has the prompt and the cleanup of the reply.
- **A container that reports its caller's location (G4).** The Vite plugin would have to pass the `file:line` of each `<Legend />` to the component.
- **Hook state in a React component's data.** React keeps hook state without names. The plugin could write the names of a component's `useState` variables into its registration, and the reader could match them to the fiber's hooks in order. A custom hook that calls `useState` shifts that order, so it is not built. A tag under the component's name reports state until then.

## Decisions taken, which you can change

- **The trigger** is Alt+Meta+click, which opens the editor on what was clicked. `setupFeedbackEngine({ shortcut })` changes the chord. A chord that ends in a key shows the pill instead, which is how the first version worked, with `Alt+Shift+F`.
- **A phone's trigger** is `button: true`, a round button on every screen that can be dragged out of the way, or `countdown()` from one of the app's menus: 5 seconds to reach the screen, then the capture.
- **Next.js gets a loader, not a compiled editor.** `withFeedbackEngine()` gives Turbopack and webpack one webpack loader that runs the same `addReact` as the Vite plugin and compiles the editor's Svelte files with the app's Svelte. Both bundlers then share one transform, and the editor stays on the app's Svelte version for the reason below. The transform parses with `oxc-parser`, the parser inside Vite 8, because a Next.js app has no Vite.
- **Element sources on a deployed site are opt-in.** `elementSources: true` writes every element's `file:line` into a production build, which a deployed preview needs. It puts the app's file paths in its HTML, so it is off by default outside the dev server.
- **ProcrastiMate** goes through the dev server. `feedbackProcrastimate()` forwards the page's calls and adds a token from the server's environment. This replaced the first plan, a CORS change in ProcrastiMate with a token in the page, because it needs no change and no deploy in ProcrastiMate and keeps the token off the page. A deployed static site has no ProcrastiMate entry. If a deployed app needs one, ProcrastiMate has to allow that origin, and the app passes `procrastimate: { url, token }`, which the client already takes.
- **Component data** is written with JavaScript literals, such as `{kg: 72.575, note: null}`.
- **React components are found, not tagged.** A capture reads React's fiber tree, and the Vite plugin registers each component of the app with its name and `file:line`. The alternatives were a tag on every component, as in Svelte, and React's own function names without a plugin. A tag on every component is work React does not need. React's own names are minified in a production build, measured as `ee`, `b`, and `h` on a Vite 8 build, and they cannot tell the app's components from a library's.
- **Every registered component is a node**, including one that only wraps others, such as `App`. Telling which component drew an element needs React's owner record, which exists only in development builds, and a rule that used it would give the two builds different trees.
- **The editor stays in Svelte for React apps.** The React plugin compiles it with the app's own Svelte version. A compiled bundle in the repository would pin the editor to one Svelte runtime, which breaks the Svelte entry point's peer range.

## Risks that tests do not cover

- **Real Safari.** The browser tests run Chromium and Playwright's WebKit, and every feature was also driven once in Google Chrome. Libraries that draw the DOM into a canvas document first-render gaps for images and fonts in Safari. Check one capture in Safari on a Mac and on a real iPhone.
- **Images without CORS, `<video>`, and iframes.** The example's media screen has a canvas, an inline SVG, and an image from another origin that allows CORS, and all three are drawn. An image from an origin that does not allow CORS, a video, and an iframe are untested.
- **A touch-screen pinch and the share sheet.** Both are written. Playwright can neither pinch nor share.
- **`__svelte_meta`.** Element locations in development builds read a field that is internal to Svelte. If Svelte renames it, untagged elements lose their locations and tagged components keep theirs.
- **React's fiber fields.** Components are read from `__reactContainer$…` on the root element and from each fiber's `tag`, `type`, `elementType`, `child`, `sibling`, `stateNode`, and `memoizedProps`. They are internal to React and are the fields its developer tools read. The browser tests cover React 18.3 and React 19. If React renames one, components found without a tag are missing, and tagged regions and elements still appear.
- **React features the tests do not render.** Suspense boundaries, `<Activity>`, and a second React root on one page are untested. A server component is rendered only in the Next.js consumer app.
- **Next.js on webpack, and `next dev`.** The browser suite builds the Next.js consumer app with Turbopack and serves it with `next start`. `next dev` with Turbopack and `next build --webpack` gave the same tree when checked by hand, and are not in the suite.
- **The Feedback button on a real phone.** The suite taps it in Chromium at a phone's width. Dragging it with a finger, and the safe-area insets of an app opened from the home screen, were not checked on a phone.
