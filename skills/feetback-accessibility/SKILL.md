---
name: feetback-accessibility
description: Make a SwiftUI screen accessible and precise to point at in Feetback captures. Use when you build or change a screen, row, card, or chart in an app that links Feetback, or when a Feetback tap selects the wrong thing.
---

# Accessibility first, Feetback tags on top

A Feetback capture is built from two sources:

1. **Elements** come from the accessibility tree: whatever VoiceOver stops on, such as a text, a button, an image, or one data point of a chart. Feetback reads only leaf elements. A container is walked through but never becomes a node, even when it has a label.
2. **Components** come from `.feedback(...)` tags. SwiftUI exposes no view hierarchy at runtime, so a tag is the only way a capture learns that a card, chart, or section exists.

A tap selects the smallest node under the finger. Where no element or tagged view sits under the point, the tap falls through to the nearest enclosing tag, usually the whole screen.

So get accessibility right for VoiceOver users, then add tags only where accessibility alone leaves a tap ambiguous.

## The rule: one tap, one obvious target

Tap anywhere on a region a person would point at and say "this": a card, a chart, a row, a section, a toolbar control, or a value inside a card. The selection must be that region, or something inside it that clearly belongs to it. It fails when:

- the tap selects something larger than the region under the finger, such as the whole screen when you tap a chart or the gap inside a card;
- a value someone would comment on, such as the big number on a card, can't be reached because it merged into a bigger element and nothing tagged sits around it;
- two different regions select the same node.

Stop there. Don't tag every `Text`, every stack, or every row's parts. A tap that selects a labeled element inside a tagged card is already precise.

## Accessibility (do this first)

- Give every icon-only button and image link an `accessibilityLabel`. Toolbar buttons built with `Button("Title", systemImage:)` already have one.
- Hide decorative images and separators with `.accessibilityHidden(true)`.
- Mark section titles with `.accessibilityAddTraits(.isHeader)`.
- Combine a row or small card whose parts read as one sentence with `.accessibilityElement(children: .combine)`, such as `"Weight, 181.6 lb, Tue"`. That's good for VoiceOver, and the combined element is the tap target. If one value inside it needs its own feedback, tag that inner view: tags are found separately from accessibility, so they survive `.combine`.
- Keep a container with independent controls as `.contain` (the default). Don't combine buttons into their surroundings.
- Charts: label the chart (`.accessibilityLabel("Steps chart")`), and let Swift Charts expose one element per data point, or set `accessibilityLabel` and `accessibilityValue` on the marks. Each data point becomes a tap target. The chart itself still needs a tag (see below).
- Don't hide meaningful content from accessibility to make a capture tidier. Fix the capture with a tag instead.

## Tags

- End the `body` of every screen and every reusable view struct (a row, a card, a sheet) with `.feedback(self)`. It names the component after its type and reports its stored properties.
- When a screen draws its sections in helper functions or inline (`private func chart(...) -> some View`), tag each region a person would point at, at the call site or at the end of the helper: `.feedback("Chart", data: plot)`, `.feedback("Summary", data: summary)`. Name it with the noun the user would say, and pass the values the region draws, not a whole store. If a section has its own inputs and state, extracting it into a struct with `.feedback(self)` is just as good.
- Always tag charts. Their data points are elements, but the axes, gutters, and the gaps between marks are not, so an untagged chart falls through to the screen.
- Tag cards and grouped boxes whose background shows a visible frame, so a tap on the padding or a label-free area selects the card.
- Tag repeated rows through their struct, so Feetback can outline the same part in sibling rows.
- Don't tag a single `Text`, `Button`, `Image`, or `Toggle`. It's already an element. Don't tag pure layout stacks that draw nothing.
- Two tags with the same frame are redundant. The inner one wins, so keep the one with the better name and data.
- Pass explicit `data:` for a view whose `@Binding` getter can trap (`Binding(get: { selection! })`): `.feedback(self)` reads bindings when the capture is taken.
- Component data is capped at 1,500 characters. Pass a summary value when the view holds a large collection.

## Verify each screen

Do this after changing a screen, in a Debug simulator build:

1. Open the screen with seeded data, then shake: `xcrun simctl notify_post <udid> com.apple.UIKit.SimulatorShake`.
2. In the editor, tap each region: every card, chart (on a mark and on an empty part of the plot), section, row, and the big values. Read the selection title under the screenshot each time. The editor canvas is a scaled screenshot, so convert an app point with the canvas frame.
3. For the whole tree, add one item, then **Share › JSON › Copy Feedback**. Read the file from the app's data container rather than the pasteboard:

   ```sh
   jq -r '.nodes[] | "\(.id)\t\(.parent // "-")\t\(.kind)\t\(.name)\t\(.label // "")\t\(.source // "")"' \
     "$(xcrun simctl get_app_container <udid> <bundle id> data)/tmp/feedback.json"
   ```

4. Check against the rule: each region has a node, each node's parent is the region that contains it on screen, and nothing a person would point at sits directly under the screen's own component.

Agent-device's XCTest runner turns accessibility on for the whole simulator, which is the same state a capture switches on, so its snapshots are a fair preview of the elements. The tags only show up in a capture.
