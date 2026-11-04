---
name: feedback-accessibility
description: Make a SwiftUI screen accessible and precise to point at in Feedback captures. Use when you build or change a screen, row, card, or chart in an app that links Feedback, or when a Feedback tap selects the wrong thing.
---

# Accessibility first, Feedback tags on top

A Feedback capture is built from two sources:

1. **Elements** come from the accessibility tree: whatever VoiceOver stops on, such as a text, a button, an image, or one data point of a chart. Feedback reads only leaf elements. A container is walked through but never becomes a node, even when it has a label.
2. **Components** come from `.feedback(...)` tags. SwiftUI exposes no view hierarchy at runtime, so a tag is the only way a capture learns that a card, chart, or section exists.

A tap selects the smallest node under the finger. Where no element or tagged view sits under the point, the tap falls through to the nearest enclosing tag, usually the whole screen.

So get accessibility right for VoiceOver users, then add tags only where accessibility alone leaves a tap ambiguous.

## The rule: one tap, one obvious target

Tap anywhere on a region a person would point at and say "this": a card, a chart, a row, a section, a toolbar control, or a value inside a card. The selection must be that region, or something inside it that clearly belongs to it. It fails when:

- the tap selects something larger than the region under the finger, such as the whole screen when you tap a chart or the gap inside a card;
- a value someone would comment on, such as the big number on a card, can't be reached because it merged into a bigger element and nothing tagged sits around it;
- two different regions select the same node.

Stop there. Margins, gaps between sections, and empty space below a short list may fall through. A tap that selects a labeled element inside a tagged card is already precise.

## Accessibility (do this first)

- Give every icon-only button and image link an `accessibilityLabel`. Toolbar buttons built with `Button("Title", systemImage:)` already have one.
- Hide decorative images, separators, and placeholder art (initials tiles, stand-in icons) with `.accessibilityHidden(true)`.
- Mark section titles with `.accessibilityAddTraits(.isHeader)`. Don't render an empty header for a section without a title: it leaves an empty element.
- Combine a row or small card whose parts read as one sentence with `.accessibilityElement(children: .combine)`, such as `"Weight, 181.6 lb, Tue"`. That's good for VoiceOver, and the combined element is the tap target.
- Keep a container with independent controls as `.contain` (the default). Don't combine buttons into their surroundings.
- A paged `TabView` that gets combined reads only "page N of M". Give it an explicit label that says what the page shows.
- Charts: label the chart (`.accessibilityLabel("Steps chart")`), and let Swift Charts expose one element per data point, or set `accessibilityLabel` and `accessibilityValue` on the marks. Each data point becomes a tap target. The chart itself still needs a tag (see below).
- Don't hide meaningful content from accessibility to make a capture tidier. Fix the capture with a tag instead.

## Tags

### What to tag

- End the `body` of every screen, sheet, and reusable view struct (a row, a card, a section) with `.feedback(self)`. It names the component after its type and reports its stored properties. A wrapper that only forwards to one child view with the same frame doesn't need its own tag.
- When a screen draws regions in helper functions or inline (`private func chart(...) -> some View`), tag each region a person would point at, where it's drawn: `.feedback("Chart", data: plot)`, `.feedback("Summary", data: summary)`. Name it with the noun the user would say. Extracting the region into a struct with `.feedback(self)` is just as good when it has its own inputs and state.
- Always tag drawings that expose no elements of their own, or only some: charts (their axes, gutters, and gaps between marks are not elements), `Canvas` and shape drawings (body maps, heat maps, progress bars), and photos.
- Tag cards and grouped boxes whose background shows a visible frame, so a tap on the padding or a label-free area selects the card.
- Tag repeated rows through their struct, so Feedback can outline the same part in sibling rows.
- Inside a `.combine`d card, tag the key values someone would comment on, even a single `Text` or `Label`, because combining removed their elements. Group a number with its unit in one stack and tag the stack. Tags are found separately from accessibility, so they survive `.combine`.

### What not to tag

- Outside a `.combine`d view, don't tag a single `Text`, `Button`, `Image`, or `Toggle`. It's already an element.
- Don't tag pure layout stacks that draw nothing.
- Two tags with the same frame are harmless, but one is enough: the inner one gets the taps and the outer one only shows in the path.

### Lists and Forms

A `List` or `Form` section has no frame a tag can measure, and a modifier on `Section` applies to each row, so don't tag `Section`. Rows of plain text already fill their cell. For a row with custom content, tag the row background, which fills the whole cell: `.listRowBackground(Color.surface.feedback("Row"))`.

### Where the tag goes

- A modifier after a `ForEach`, after a bare `if`/`else` at the top of `body`, or on a `Section` either doesn't compile or tags every child. Put the tag on the branch's view, or wrap the branches in a `Group` with one child per branch.
- Put the tag before a screen-margin `.padding(.horizontal)`, or the region includes the margins.
- A design-system container that is a region in its own right (a truncated list, a legend) tags itself. Give it `file: String = #fileID, line: Int = #line` parameters and pass them to `.feedback(_:data:file:line:)`, so the capture names the call site instead of the container's own file.

### Data

- Pass values the region already computed for drawing. Never `map`, `filter`, sort, or look things up just to build `data:`: it runs on every render.
- Omit `data:` when the elements inside already name everything.
- Component data is capped at 1,500 characters. Pass a summary, such as a count, when the view holds a large collection.
- Pass explicit `data:` for a view whose `@Binding` getter can trap (`Binding(get: { selection! })`): `.feedback(self)` reads bindings when the capture is taken.

## Verify each screen

Do this after changing a screen, in a Debug simulator build with realistic data:

1. Open the screen, shake with `xcrun simctl notify_post <udid> com.apple.UIKit.SimulatorShake`, and within 5 s press the **Send feedback** button the shake shows in the top-right corner. The editor can take about 3 s to open over a long list.
2. Export the tree: add one item, then **Share › JSON**. The file is written when the share sheet opens. Read it from the app's data container, not the pasteboard: `"$(xcrun simctl get_app_container <udid> <bundle id> data)/tmp/feedback.json"`.
3. Replay every tap with `scripts/taps.py` from this skill's folder. Without a local copy, stream it from GitHub:

   ```sh
   gh api repos/smirea/feedback-engine/contents/skills/feedback-accessibility/scripts/taps.py \
     -H 'Accept: application/vnd.github.raw' | python3 - feedback.json
   ```

   It mirrors Feedback's hit testing on an 8 pt grid and prints the share of taps that fall through to a screen or layer root, the bands where most of a row falls through, and the elements that sit directly under a root. Every band should be a margin, a gap, or empty space, and every listed element should be a precise target on its own, such as a lone button. Anything else is a missing tag. This covers the parts of a long screen that the editor canvas doesn't show without scrolling.
4. Spot-check with real taps on the regions you changed: every card, a chart's mark and its empty plot area, a row, and the key values. Read the selection title under the screenshot. The canvas is a scaled screenshot, so convert app points with its frame. With agent-device, use plain coordinate presses and `agent-device screenshot` to read the result. Taking snapshots between presses, or pressing with `--settle`, has stopped the canvas from receiving taps.
5. Check that VoiceOver output didn't get worse: agent-device's snapshot lists the elements VoiceOver reads.

Agent-device's XCTest runner turns accessibility on for the whole simulator, which is the same state a capture switches on, so its snapshots are a fair preview of the elements. The tags only show up in a capture.
