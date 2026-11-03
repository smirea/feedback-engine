# Feetback

**Point at your app. Say what's wrong. Hand an agent the exact component and line of code.**

Shake the device, tap any component on the frozen screenshot, and write what should change. Feetback exports one file that names every component you flagged, where it lives in the source, and the data it was showing, so an agent can act on the feedback without guessing.

<p align="center">
  <img src="docs/editor.png" alt="The Feetback editor: a frozen screenshot with the Groceries row selected, showing ListRow, App/ListsScreen.swift:81 and its data" width="270">
  &nbsp;&nbsp;&nbsp;
  <img src="docs/export.png" alt="The exported feedback.png: the screenshot with three numbered boxes, each linked to a card with the component, its file:line, and the note" width="560">
</p>

<p align="center"><sub>Left: tap a component in the editor. Right: the <code>feedback.png</code> it exports, ready to paste into a chat with an agent.</sub></p>

<p align="center">
  <img src="docs/demo.gif" alt="Adding three pieces of feedback, then opening the exported image" width="270"><br>
  <sub>Three notes and the exported image in about 10 seconds. <a href="docs/demo.mp4">Full quality video</a></sub>
</p>

Prefer structured data? Switch the export to JSON for the whole component tree, each component's data, and the app context you attached.

Platform packages live under `packages/`. iOS is available now; a Svelte package is planned and will produce the same report ([spec/report.md](spec/report.md)).

## iOS

Requires iOS 17 or later and Swift 6.

### Add the package

In Xcode, add the package from this repository (or a local checkout with **Add Local…**) and link the `Feetback` library to your app target. In a `Package.swift`:

```swift
.package(url: "https://github.com/smirea/feedback-engine", branch: "master"),
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
- `Feetback.context(name) { value }` attaches app state to every JSON export. The closure runs when a capture is taken.
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

Untagged views still appear: buttons, text, images, and headers come from the accessibility tree and attach to the nearest tagged component around them. A button or `NavigationLink` merges everything inside it into one element, such as `Button "Work, 3"`, so the text and counts inside it can't be picked one by one. A tagged component inside the button still can, and its parent is the button. Tag an inner view when it needs feedback of its own.

### Give feedback

1. Shake the device. In the simulator, use **Device › Shake**.
2. Tap the screenshot. The most specific component or element under your finger is selected, and the same part in sibling components, such as the same button in every row, is outlined faintly. Scroll the screenshot to reach content that was off screen. Scrolling also works while you type.
3. Under the screenshot, the selection sits between its parent on the left and its child on the right. Tap either one to move the selection up or down the hierarchy.
4. Type the feedback and press the arrow. Repeat for as many items as you need.
5. Open the list to review or remove items, and to see the context that will be attached.
6. Pick the export format in the list. **Image** shares one `feedback.png` with the boxes, each item's text and code location, and the environment. **JSON** shares one `feedback.json` with every item, the whole component tree, the component data, and the attached context, without the screenshot. The choice is remembered.
7. Tap **Share**. **Copy Feedback** puts the export on the clipboard, ready to paste into a chat with an agent. Other share targets, such as Messages, Notes, or Files, receive it too.
8. Tap **Close** to return to the app. If some items were never shared, Feetback asks before it discards them. The text field that had focus before the shake gets it back.

While the editor is open, VoiceOver and UI automation see only the editor. Its text stops growing at the largest standard Dynamic Type size, so the screenshot keeps room at accessibility sizes.

### How capture works

- The screenshot and the tagged components are read at the moment you shake. Each `.feedback` modifier places a plain `UIView` behind its view, and a capture walks the view hierarchy to find them. Tagging costs nothing per frame.
- Component nesting follows the SwiftUI hierarchy, so parents in the export are the real logical parents.
- When the screen has a scrolling list or scroll view that covers at least half of it, the capture covers that content at full length. Feetback covers the app with the frozen screenshot, scrolls through the content one screen at a time, reads each step, and then restores the scroll position. The editor opens at the part that was on screen.
- SwiftUI only exposes accessibility elements while an assistive client is running. During a capture Feetback turns on accessibility automation, which is the same private switch XCTest and Cash App's AccessibilitySnapshot use, and then restores it. The first capture in a process pauses for about a second while UIKit loads its accessibility support. Later captures take a few milliseconds.
- Presented sheets, alerts, and open menus are separate layers. Taps on a sheet only select what is inside the sheet, and the items of an open menu can be picked one by one.
- The keyboard is drawn by a system process, so a capture can't contain it. Feetback draws a gray "Keyboard" block in its place, so the bars above it stay where they were, and taps there select the keyboard instead of the content under it.

### Limits

- Only the largest vertical scroll view is captured at full length, and only when nothing is shown over the screen, such as a sheet, a menu, the keyboard, or an extra window for a toast. Other scroll views, such as horizontal carousels, show what was on screen.
- A full-length capture stops at 16,000 pixels, about 5,300 points on a 3x screen. A capture with a long list also takes longer, because each screen of content is read in turn.
- Scrolling during a capture is real scrolling. Code that reacts to it, such as infinite-scroll loading, runs. Pinned section headers appear once per screen of content.
- The accessibility switch is private API, looked up at runtime. If a future iOS removes it, captures still work with tagged components only. Be careful about shipping it in App Store builds.
- `.feedback(self)` reads `@Binding` values when you shake. A binding whose getter can trap, such as `Binding(get: { selection! })`, crashes the capture the same way it would crash a redraw. Pass explicit `data:` for those views.
- Components inside lazy containers, such as `List` and `LazyVStack`, appear only for rows that exist on screen, except in the scroll view captured at full length.

## Example app

`examples/todo-ios` is a small todo app with lists, a list detail screen, an edit sheet, and settings. Every screen is tagged. Run it with:

```sh
cd examples/todo-ios
./scripts/run
```

## Development

```sh
swift build   # compiles the package for macOS
swift test    # tree building, hit-testing, stitching, JSON export, and value description tests
```
