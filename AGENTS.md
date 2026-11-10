# Feedback

In-app feedback packages, one per platform. Read `README.md` for the integration API, `spec/report.md` for the shared export format, and `spec/features.md` for what each platform does. Keep every platform's output identical to `spec/report.md`, and update it in the same change when the format moves.

`spec/features.md` has one row per feature with a status for iOS and for the web. Add or update the row in the same change that adds, changes, or removes behavior on any platform. `bun test spec` fails on a row without a status for every platform.

# Layout

- `Package.swift` sits at the repository root so apps can add the repo as a Swift package. Its sources are in `packages/ios`.
- `packages/ios/Sources/Feedback`: the pure core (`Model`, `TreeBuilder`, `Report`, `Describer`, `Session`) compiles on macOS and is unit tested. Files that need UIKit are wrapped in `#if canImport(UIKit)`.
- `skills/feedback-accessibility`: the playbook apps' agents follow to make screens accessible and precise to point at. Update it in the same change when tagging, hit-testing, or element collection changes.
- `examples/todo-ios`: the demo app. It links the package through a local package reference to `../..`.
- `package.json` sits at the repository root for the same reason: apps will install `github:smirea/feedback-engine`. It has no `exports` map yet. Phase 1 of `docs/web-plan.md` adds one that points into `packages/web/src`. The root is also the Bun workspace for `examples/*`.
- `packages/web` (planned): the web package `@smirea/feedback-engine`, one entry point per framework, producing the same exports. `docs/web-plan.md` has its shape and the order of the work.
- `examples/todo-svelte`: the web demo app, a SvelteKit SPA that mirrors `examples/todo-ios`.

# Development

- `bun run lint`, `bun run typecheck`, and `bun test` cover the TypeScript side. The commit hook runs them on staged files. `.github/CI.md` describes CI.
- `bun run dev` serves `examples/todo-svelte` on `UI_PORT` from the root `.env`. A worktree gets its own port in `.env.local`. After editing `.env`, run `bun run env:generate` and commit `examples/todo-svelte/env.ts` as generated.
- SvelteKit 3 has no `$lib` alias. The example imports with relative paths.
- `swift test` runs the core tests on macOS. Test behavior through `TreeBuilder.build`, `Stitch.scene`, `Capture.hitTest`, and `Report.json` with literal expected values.
- `xcodebuild -scheme Feedback -destination 'generic/platform=iOS Simulator' build` compiles the UIKit half.
- Run the example with `cd examples/todo-ios && ./scripts/run -t "$(agent-simulator udid)" --headless`. Drive the simulator only through the command T3 Code's `device_open` returns.
- The example app is not in the `com.stefan.shared` keychain group, so **ProcrastiMate** shows the missing-entitlement message there. Test a post from an app in the group, such as a-better-me, never against the real server: run a scratch ProcrastiMate server on the Debug port (`PROCRASTIMATE_DATABASE=/tmp/<dir>/test.sqlite API_PORT=6121 bun src/index.ts` in `~/code/procrastimate/server`), install ProcrastiMate's Debug build on the same simulator and sign up there with email and password, which writes the shared session, then post. `GET /api/view` on the scratch server shows the task.
- agent-device has no shake gesture. Trigger the real shake with `xcrun simctl notify_post <udid> com.apple.UIKit.SimulatorShake`, then press `label="Add Feedback"` within 5 s to open the editor.
- The editor canvas is a scaled screenshot. To tap an app point `(x, y)`, convert it with the canvas frame from `device_screenshot`.
- Read an export with **Share › Image** (or JSON, or ZIP) **› Copy Feedback**, or from the app's `tmp/feedback.*` (`xcrun simctl get_app_container <udid> <bundle id> data`). The simulator's pasteboard has come back empty after a copy, so the files are the reliable read. For JSON, `agent-device clipboard read` prints it. For an image, `xcrun simctl pbsync <udid> host` copies the PNG to the Mac pasteboard; the sync races, so retry until `osascript -e 'clipboard info'` lists PNGf.
- agent-device's XCTest runner turns accessibility on for the whole simulator. To check what a real user's capture contains, shake on a simulator with no runner attached and tap **Add Feedback** in Device Hub or Simulator.app (computer use can do it), then attach agent-device to read the result.
