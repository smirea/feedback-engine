# Feetback

Precise, in-app feedback for the apps you build. Shake the device, tap a component on the frozen screenshot, and write what should change. Feetback shares an annotated image and a markdown report that names each component, its source location, and the data it was showing, so an agent can act on it without guessing.

Platform packages live under `packages/`. iOS is available now; a Svelte package is planned and will produce the same report ([spec/report.md](spec/report.md)).

## iOS

Requires iOS 17 or later and Swift 6.

### Add the package

In Xcode, add the package from this repository (or a local checkout with **Add Local…**) and link the `Feetback` library to your app target. In a `Package.swift`:

```swift
.package(url: "https://github.com/smirea/feetback-engine", branch: "master"),
```

### Turn it on

```swift
import Feetback

@main
struct MyApp: App {
    @State private var store: Store

    init() {
        let store = Store()
        _store = State(initialValue: store)
        Feetback.enable()
        Feetback.context("Store") { store }
    }
    // ...
}
```

- `Feetback.enable()` turns on shake-to-feedback. Wrap it in `#if DEBUG` if you only want it in development builds.
- `Feetback.context(name) { value }` attaches app state to every report. The closure runs when a capture is taken.
- `Feetback.present()` opens the editor from your own trigger, such as a settings button.

### Name your components

Add one modifier at the end of each view's `body`:

```swift
struct TodoRow: View {
    let item: TodoItem
    @State private var isExpanded = false

    var body: some View {
        HStack { /* ... */ }
            .feedback(self)
    }
}
```

`.feedback(self)` names the component after its type and reports its stored properties, `@State`, `@Binding`, and `@Bindable` values. `@Environment` values and closures are skipped. To choose the name or the data yourself, use `.feedback("TodoRow", data: item)`.

Untagged views still appear: buttons, text, images, and headers come from the accessibility tree and attach to the nearest tagged component around them.

### Give feedback

1. Shake the device. In the simulator, use **Device › Shake**.
2. Tap the screenshot. The most specific component or element under your finger is selected.
3. Drag the slider, or tap a breadcrumb, to widen the selection to a parent component.
4. Type the feedback and press the arrow. Repeat for as many items as you need.
5. Open the list to review or remove items, and to see the context that will be attached.
6. Tap **Share**. **Copy Feedback** puts the annotated image and the report on the clipboard, ready to paste into a chat with an agent. Other share targets, such as Messages, Notes, or Files, receive both too.

### How capture works

- The screenshot and the tagged components are read at the moment you shake. Each `.feedback` modifier places a plain `UIView` behind its view, and a capture walks the view hierarchy to find them. Tagging costs nothing per frame.
- Component nesting follows the SwiftUI hierarchy, so parents in the report are the real logical parents.
- SwiftUI only exposes accessibility elements while an assistive client is running. During a capture Feetback turns on accessibility automation, which is the same private switch XCTest and Cash App's AccessibilitySnapshot use, and then restores it. The first capture in a process pauses for about a second while UIKit loads its accessibility support. Later captures take a few milliseconds.
- Presented sheets are separate layers. Taps on a sheet only select what is inside the sheet.

### Limits

- Only the visible screen is captured. Content scrolled off screen is not in the image or the tree.
- The accessibility switch is private API, looked up at runtime. If a future iOS removes it, captures still work with tagged components only. Be careful about shipping it in App Store builds.
- `.feedback(self)` reads `@Binding` values when you shake. A binding whose getter can trap, such as `Binding(get: { selection! })`, crashes the capture the same way it would crash a redraw. Pass explicit `data:` for those views.
- Components inside lazy containers, such as `List` and `LazyVStack`, appear only for rows that exist on screen.

## Example app

`examples/todo-ios` is a small todo app with lists, a list detail screen, an edit sheet, and settings. Every screen is tagged. Run it with:

```sh
cd examples/todo-ios
./scripts/run
```

## Development

```sh
swift build   # compiles the package for macOS
swift test    # tree building, hit-testing, report, and value description tests
```

CI runs both, plus a Release simulator build of the example app.
