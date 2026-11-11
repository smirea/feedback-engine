# Web package: what is left

The web package, `@smirea/feedback-engine`, is in `packages/web/src` and on par with the iOS package wherever a browser allows it. [`spec/features.md`](../spec/features.md) is the row-by-row record. This file lists the rows that are still `planned` for the web, and the risks that tests do not cover. Delete an item when it lands.

## Planned

- **A shake on phones (T8).** It needs the `devicemotion` permission, which iOS Safari grants only from a tap, and a physical phone to check it on. Until then a phone opens the editor from the app's own control.
- **A task name from an on-device model (P5).** Chrome has a built-in model behind `LanguageModel`. On the machine this was developed on, Chrome 156 reported it as `unavailable`, so the code could not be checked and was not written. `taskTitle` in the core already has the prompt and the cleanup of the reply.
- **A container that reports its caller's location (G4).** The Vite plugin would have to pass the `file:line` of each `<Legend />` to the component.
- **React without Vite.** `feedbackEngineReact()` is a Vite plugin, and it does two jobs another bundler would need: it registers the app's components, and it compiles the editor's Svelte files. A Next.js app on webpack or Turbopack needs both as a loader, or the editor as a compiled bundle. Decide that when such an app needs Feedback.
- **Hook state in a React component's data.** React keeps hook state without names. The plugin could write the names of a component's `useState` variables into its registration, and the reader could match them to the fiber's hooks in order. A custom hook that calls `useState` shifts that order, so it is not built. A tag under the component's name reports state until then.

## Decisions taken, which you can change

- **The shortcut** is `Alt+Shift+F`, and `setupFeedbackEngine({ shortcut })` changes it.
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
- **React features the tests do not render.** Suspense boundaries, `<Activity>`, server components, and a second React root on one page are untested.
