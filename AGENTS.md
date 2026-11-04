# Feetback

In-app feedback packages, one per platform. Read `README.md` for the integration API and `spec/report.md` for the shared export format. Keep every platform's output identical to that spec, and update the spec in the same change when the format moves.

# Layout

- `Package.swift` sits at the repository root so apps can add the repo as a Swift package. Its sources are in `packages/ios`.
- `packages/ios/Sources/Feetback`: the pure core (`Model`, `TreeBuilder`, `Report`, `Describer`, `Session`) compiles on macOS and is unit tested. Files that need UIKit are wrapped in `#if canImport(UIKit)`.
- `examples/todo-ios`: the demo app. It links the package through a local package reference to `../..`.
- `packages/svelte` (planned): the web package, producing the same exports.

# Development

- `swift test` runs the core tests on macOS. Test behavior through `TreeBuilder.build`, `Stitch.scene`, `Capture.hitTest`, and `Report.json` with literal expected values.
- `xcodebuild -scheme Feetback -destination 'generic/platform=iOS Simulator' build` compiles the UIKit half.
- Run the example with `cd examples/todo-ios && ./scripts/run -t "$(agent-simulator udid)" --headless`. Drive the simulator only through the command T3 Code's `device_open` returns.
- Test the ProcrastiMate post against a scratch ProcrastiMate server, never the real one: in `~/code/procrastimate/server`, `PROCRASTIMATE_DATABASE=/tmp/<dir>/test.sqlite API_PORT=<port> bun src/index.ts`, sign up through `/api/auth/sign-up/email`, mint a personal token with `POST /api/ai-tokens` (`aiUserId` is your own id from `/api/me`), and point the example at it with `xcrun simctl spawn <udid> defaults write com.stefan.tododemo procrastimateURL http://localhost:<port>` and the same for `procrastimateToken`. `GET /api/view` then shows the task.
- agent-device has no shake gesture. Trigger the real shake with `xcrun simctl notify_post <udid> com.apple.UIKit.SimulatorShake`.
- The editor canvas is a scaled screenshot. To tap an app point `(x, y)`, convert it with the canvas frame from `device_screenshot`.
- Read an export with **Share › Image** (or JSON, or ZIP) **› Copy Feedback**, or from the app's `tmp/feedback.*` (`xcrun simctl get_app_container <udid> <bundle id> data`). The simulator's pasteboard has come back empty after a copy, so the files are the reliable read. For JSON, `agent-device clipboard read` prints it. For an image, `xcrun simctl pbsync <udid> host` copies the PNG to the Mac pasteboard; the sync races, so retry until `osascript -e 'clipboard info'` lists PNGf.
- agent-device's XCTest runner turns accessibility on for the whole simulator. To check what a real user's capture contains, shake on a simulator with no runner attached, then attach agent-device to read the result.
