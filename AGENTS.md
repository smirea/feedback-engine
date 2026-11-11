# Feedback

In-app feedback packages, one per platform. Read `README.md` for the integration API, `spec/report.md` for the shared export format, and `spec/features.md` for what each platform does. Keep every platform's output identical to `spec/report.md`, and update it in the same change when the format moves.

`spec/features.md` has one row per feature with a status for iOS, Svelte, and React. Add or update the row in the same change that adds, changes, or removes behavior on any platform. `bun test spec` fails on a row without a status for every platform.

# Layout

- `Package.swift` sits at the repository root so apps can add the repo as a Swift package. Its sources are in `packages/ios`.
- `packages/ios/Sources/Feedback`: the pure core (`Model`, `TreeBuilder`, `Report`, `Describer`, `Session`) compiles on macOS and is unit tested. Files that need UIKit are wrapped in `#if canImport(UIKit)`.
- `skills/feedback-accessibility`: the playbook apps' agents follow to make screens accessible and precise to point at. Update it in the same change when tagging, hit-testing, or element collection changes.
- `examples/todo-ios`: the demo app. It links the package through a local package reference to `../..`.
- `package.json` sits at the repository root for the same reason: apps install `github:smirea/feedback-engine`, and its `exports` map points into `packages/web/src`. The package ships source, with no build step. The root is also the Bun workspace for `examples/*`.
- `packages/web/src`: the web package `@smirea/feedback-engine`.
  - `core`: pure TypeScript, unit tested. The model, hit-testing, annotations, the session rules, the report, the card layout, the tree builder, and the value describer.
  - `dom`: browser code without a framework. The scene reader, the screenshot, the image export, sharing, and the ProcrastiMate client.
  - `editor`: the pill and the editor, in Svelte, mounted in a shadow root. Every component has `<svelte:options css="injected" />`, because other styles would not reach inside the shadow root. Keep runes in `.svelte` files. A `.svelte.ts` module with type syntax breaks an app's dev server, which pre-bundles the package from `node_modules` without removing types.
  - `editor/setup.ts`: `setupFeedbackEngine`, which both entry points export.
  - `svelte`: the Svelte entry point, with the `feedback` attachment.
  - `react`: the React entry point, with the `feedback` ref and `components.ts`, which reads React's fiber tree for the components the Vite plugin registered. It imports nothing from `react`. `public.d.ts` is what an app's compiler reads instead of the source, and `public.test.ts` fails the type check when the two drift.
  - `vite`: the build plugins, in plain JavaScript so Node loads them from `node_modules`. `index.js` has the Svelte preprocessor and the ProcrastiMate proxy, which also tells the page whether it has a token. `react.js` has the React plugin, which also compiles the editor's Svelte files for a React app.
- `spec/fixtures/capture.json`: one tree with the answers both platforms must give. `swift test` and `bun test` both read it. Change the fixture when shared logic changes, and both suites must pass on it.
- `docs/web-plan.md`: what is left for the web package.
- `examples/todo-svelte` and `examples/todo-react`: the web demo apps, a SvelteKit SPA and a React app with React Router. They mirror `examples/todo-ios` and each other: the same screens, markup, and styles, so one browser suite runs on both. Change them together.

# Development

- `bun run lint`, `bun run typecheck`, and `bun test` cover the TypeScript side. The commit hook runs them on staged files. `.github/CI.md` describes CI.
- `bun run test:web` drives both example apps with Playwright in Chromium and WebKit, on a dev server and a production build. Every test in `feedback.e2e.ts` runs once per app, and `expected` at its top holds what differs between them. It starts its own servers beside the `bun run dev` ports, and a stand-in ProcrastiMate server. `consumer.e2e.ts` packs the package, installs it into a plain Svelte app and a plain React 18 app outside the repository, and runs each with Node, because the examples' workspace link skips what Vite does to a package in `node_modules`. The React app has stricter compiler options than the package, and its `tsc` run fails if an app ever compiles the package's source. Test web behavior there, through the page: `present`, `tap`, and `exportReport` in `packages/web/e2e/app.ts`.
- ProcrastiMate is optional on every platform. On the web the token is the switch: `feedbackProcrastimate()` writes the proxy's path into `import.meta.env.FEEDBACK_PROCRASTIMATE` only when it has one, and `setupFeedbackEngine()` reads it. The browser suite's servers and its build get a token. The React app that installs the packed package gets none, and checks that the entry is gone. On iOS the switch is the keychain group in the app's entitlements.
- The root `package.json` is also the package apps install, so it has no install script: package managers run or flag a dependency's install scripts. Git hooks come from `bun run hooks`, which a T3 worktree runs through `worktree:setup`.
- `Session` is plain TypeScript and not reactive. In the editor, change it only inside `act`, and draw only from `view`.
- To check a ProcrastiMate post from the web against the real server code, run the scratch server described below, sign up with `POST /api/auth/sign-up/email`, and start the example with `PROCRASTIMATE_URL` and `PROCRASTIMATE_TOKEN` set to the scratch server and the `set-auth-token` header of the sign-up.
- `bun run dev` serves `examples/todo-svelte` on `UI_PORT` from the root `.env`, and `bun run dev:react` serves `examples/todo-react` on `UI_PORT + 5`. A worktree gets its own ports in `.env.local`. In the main checkout, localias forwards `https://feedback-engine.localhost` to `UI_PORT`, so the Svelte example answers there too. A worktree's ports have no name. After editing `.env`, run `bun run env:generate` and commit the root `env.ts` as generated.
- A React component is a node only when the plugin registered it. Without a registration the fiber tree cannot tell the app's components from a library's, and a minified build has no names. Keep that rule: a fallback to React's own function names would give a development build and a production build different trees.
- SvelteKit 3 has no `$lib` alias. The example imports with relative paths.
- `swift test` runs the core tests on macOS. Test behavior through `TreeBuilder.build`, `Stitch.scene`, `Capture.hitTest`, and `Report.json` with literal expected values.
- `xcodebuild -scheme Feedback -destination 'generic/platform=iOS Simulator' build` compiles the UIKit half.
- Run the example with `cd examples/todo-ios && ./scripts/run -t "$(agent-simulator udid)" --headless`. Drive the simulator only through the command T3 Code's `device_open` returns.
- The example app is not in the `com.stefan.shared` keychain group, so its Share menu has no **ProcrastiMate** entry. Test a post from an app in the group, such as a-better-me, never against the real server: run a scratch ProcrastiMate server on the Debug port (`PROCRASTIMATE_DATABASE=/tmp/<dir>/test.sqlite API_PORT=6121 bun src/index.ts` in `~/code/procrastimate/server`), install ProcrastiMate's Debug build on the same simulator and sign up there with email and password, which writes the shared session, then post. `GET /api/view` on the scratch server shows the task.
- agent-device has no shake gesture. Trigger the real shake with `xcrun simctl notify_post <udid> com.apple.UIKit.SimulatorShake`, then press `'role=button label="Add Feedback"'` within 5 s to open the editor. The label alone also matches the pill's window, and that press lands in the middle of the screen.
- The editor canvas is a scaled screenshot. To tap an app point `(x, y)`, convert it with the canvas frame from `device_screenshot`.
- Read an export with **Share › Image** (or JSON, or ZIP) **› Copy Feedback**, or from the app's `tmp/feedback.*` (`xcrun simctl get_app_container <udid> <bundle id> data`). The simulator's pasteboard has come back empty after a copy, so the files are the reliable read. For JSON, `agent-device clipboard read` prints it. For an image, `xcrun simctl pbsync <udid> host` copies the PNG to the Mac pasteboard; the sync races, so retry until `osascript -e 'clipboard info'` lists PNGf.
- agent-device's XCTest runner turns accessibility on for the whole simulator. To check what a real user's capture contains, shake on a simulator with no runner attached and tap **Add Feedback** in Device Hub or Simulator.app (computer use can do it), then attach agent-device to read the result.
