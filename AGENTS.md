# Feetback

In-app feedback packages, one per platform. Read `README.md` for the integration API and `spec/report.md` for the shared report format. Keep every platform's output identical to that spec, and update the spec in the same change when the format moves.

# Layout

- `Package.swift` sits at the repository root so apps can add the repo as a Swift package. Its sources are in `packages/ios`.
- `packages/ios/Sources/Feetback`: the pure core (`Model`, `TreeBuilder`, `Report`, `Describer`, `Session`) compiles on macOS and is unit tested. Files that need UIKit are wrapped in `#if canImport(UIKit)`.
- `examples/todo-ios`: the demo app. It links the package through a local package reference to `../..`.
- `packages/svelte` (planned): the web package, producing the same report.

# Development

- `swift test` runs the core tests on macOS. Test behavior through `TreeBuilder.build`, `Capture.hitTest`, and `Report.markdown` with literal expected values.
- `xcodebuild -scheme Feetback -destination 'generic/platform=iOS Simulator' build` compiles the UIKit half.
- Run the example with `cd examples/todo-ios && ./scripts/run -t "$(agent-simulator udid)" --headless`. Drive the simulator only through the command T3 Code's `device_open` returns.
- agent-device has no shake gesture. Trigger the real shake with `xcrun simctl notify_post <udid> com.apple.UIKit.SimulatorShake`.
- The editor canvas is a scaled screenshot. To tap an app point `(x, y)`, convert it with the canvas frame from `device_screenshot`.
- Read a shared report with **Share › Copy Feedback**, then `agent-device clipboard read` for the markdown. `xcrun simctl pbsync <udid> host` copies the PNG to the Mac pasteboard.
- agent-device's XCTest runner turns accessibility on for the whole simulator. To check what a real user's capture contains, shake on a simulator with no runner attached, then attach agent-device to read the result.
