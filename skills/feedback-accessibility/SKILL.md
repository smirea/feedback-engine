---
name: feedback-accessibility
description: Make a SwiftUI, Svelte, or React screen accessible and precise to point at in Feedback captures. Use when you build or change a screen, row, card, or chart in an app that uses Feedback, or when a Feedback tap selects the wrong thing.
---

# Accessibility first, Feedback tags on top

A Feedback capture is built from two sources:

1. **Elements**: what assistive technology reads, such as a text, a button, an image, or one data point of a chart. Only leaf elements become nodes. A container is walked through, even when it has a label.
2. **Components**: the named regions of your app, such as a card, a row, or a screen.

Each package finds them its own way:

| Package | Elements come from | Components come from |
| --- | --- | --- |
| [SwiftUI](#swiftui) | The accessibility tree | `.feedback(...)` tags. SwiftUI exposes no view hierarchy at runtime. |
| [Svelte](#svelte) | The DOM, with ARIA roles and names | `{@attach feedback(...)}` tags. A compiled component leaves no record in the page. |
| [React](#react) | The DOM, with ARIA roles and names | React's own component tree, with no tag. `ref={feedback(...)}` tags add regions drawn inline. |

A tap selects the smallest node under the finger. Where no element or component sits under the point, the tap falls through to the nearest enclosing component, usually the whole screen. The one exception: inside the box of a node that already has feedback, a tap selects that item so its feedback can be edited, and a second tap on the same spot drills down to the smallest node.

So get accessibility right for people who use assistive technology, then add tags only where a tap is still ambiguous.

## The rule: one tap, one obvious target

Tap anywhere on a region a person would point at and say "this": a card, a chart, a row, a section, a toolbar control, or a value inside a card. The selection must be that region, or something inside it that clearly belongs to it. It fails when:

- the tap selects something larger than the region under the finger, such as the whole screen when you tap a chart or the gap inside a card;
- a value someone would comment on, such as the big number on a card, can't be reached because it merged into a bigger element and no component sits around it;
- two different regions select the same node.

Stop there. Margins, gaps between sections, and empty space below a short list may fall through. A tap that selects a labeled element inside a component is already precise.

Read the section for your package. Each one stands alone.

## SwiftUI

### Accessibility (do this first)

- Give every icon-only button and image link an `accessibilityLabel`. Toolbar buttons built with `Button("Title", systemImage:)` already have one.
- Hide decorative images, separators, and placeholder art (initials tiles, stand-in icons) with `.accessibilityHidden(true)`.
- Mark section titles with `.accessibilityAddTraits(.isHeader)`. Don't render an empty header for a section without a title: it leaves an empty element.
- Combine a row or small card whose parts read as one sentence with `.accessibilityElement(children: .combine)`, such as `"Weight, 181.6 lb, Tue"`. That's good for VoiceOver, and the combined element is the tap target.
- Keep a container with independent controls as `.contain` (the default). Don't combine buttons into their surroundings.
- A paged `TabView` that gets combined reads only "page N of M". Give it an explicit label that says what the page shows.
- Charts: label the chart (`.accessibilityLabel("Steps chart")`), and let Swift Charts expose one element per data point, or set `accessibilityLabel` and `accessibilityValue` on the marks. Each data point becomes a tap target. The chart itself still needs a tag (see below).
- Don't hide meaningful content from accessibility to make a capture tidier. Fix the capture with a tag instead.

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

### Verify each screen

Do this after changing a screen, in a Debug simulator build with realistic data:

1. Open the screen, shake with `xcrun simctl notify_post <udid> com.apple.UIKit.SimulatorShake`, and within 5 s press the **Add Feedback** pill the shake shows at the top center. With agent-device, press `'role=button label="Add Feedback"'`. The label alone also matches the pill's window, and that press lands in the middle of the screen. The editor can take about 3 s to open over a long list.
2. Export the tree: add one item, then **Share › JSON**. The file is written when the share sheet opens. Read it from the app's data container, not the pasteboard: `"$(xcrun simctl get_app_container <udid> <bundle id> data)/tmp/feedback.json"`.
3. [Replay every tap](#replay-every-tap) on the export.
4. Spot-check with real taps on the regions you changed: every card, a chart's mark and its empty plot area, a row, and the key values. Read the selection title under the screenshot. Check targets before adding any feedback, or tap twice inside a numbered box, since a first tap there selects the item instead of the smallest node. The canvas is a scaled screenshot, so convert app points with its frame: the element named `Screenshot` inside the scroll area of the same name, from `agent-device snapshot -i --json`. With agent-device, press the converted point with `--settle`. The diff it prints has the new selection title and its `file:line`.
5. Check that VoiceOver output didn't get worse: agent-device's snapshot lists the elements VoiceOver reads.

Agent-device's XCTest runner turns accessibility on for the whole simulator, which is the same state a capture switches on, so its snapshots are a fair preview of the elements. The tags only show up in a capture.

## Svelte

### Accessibility (do this first)

- Use the element that has the role: `<button>`, `<a href>`, `<input>`, `<select>`, `<h1>` to `<h6>`. A `<div onclick>` has no role, so it is not an element in a capture. If you must build a control from a `<div>`, give it its `role`.
- Give every icon-only button an `aria-label`, and every `<img>` an `alt`. An image with `alt=""` is decorative and left out.
- Hide decorative marks, such as a colored dot or an initials tile, with `aria-hidden="true"`.
- Name a field with a `<label>` around it or an `aria-label`. The capture reads the name and the value together, such as `Text field "Title, Bananas"`.
- A button or a link merges everything inside it into one element, such as `Link "Work 3"`. That is right for a row that reads as one sentence. Tag an inner part when it needs feedback of its own.
- Landmarks, lists, and groups (`<main>`, `<nav>`, `<section>`, `<ul>`, `role="group"`) are walked through and never become nodes, even with a label. Tag one when a tap on its padding should select it.
- A modal `<dialog>`, an open `popover`, and an `aria-modal="true"` dialog are layers of their own. Use one of them for anything that covers the page, so taps on it select only what is inside it.

### Tags

- Put `{@attach feedback()}` on the root element of every screen, dialog, and reusable component. It names the component after its file and reports its props and `$state` variables. A route file is named after its folders, so name a screen yourself: `{@attach feedback('ListsScreen', () => ({ filter }))}`.
- Tag a region drawn inline where it is drawn: `{@attach feedback('Chart', () => plot)}`.
- Always tag drawings that expose no elements: an `<svg>` chart, a `<canvas>`, a photo.
- Tag cards and grouped boxes whose background shows a visible frame.
- A component needs one root element to tag. A component that renders several siblings has no frame, so tag each sibling or wrap them.
- Don't tag an element with `display: contents`. It has no box.
- Outside a button or a link, don't tag a single text, button, image, or field. It's already an element.

### Data

- The data function runs when a capture is taken, never while rendering, so it may read whatever the component has. Keep it cheap anyway: a capture runs it for every tag on the page.
- A bare `feedback()` reports every prop and every `$state` variable. Pass a function when that is too much, such as a component that receives a large list: `{@attach feedback(undefined, () => ({ count: items.length }))}`.
- A class shows under its own name, such as `TodoStore(lists: [...])`. Give it a `toFeedback()` method to choose what it reports.

### A way to open Feedback

- With a mouse, Alt+Meta+click on anything opens the editor with that element selected. There is nothing to build.
- A phone has no modifier keys, and a shake does not work on the web yet. Add an entry to a menu the app already has, such as Settings or an account menu, that starts a countdown: `<button onclick={() => globalThis.__feedbackEngine?.countdown()}>Send Feedback</button>`. The page shows a pill that counts down from 5 and then captures, so the person has time to leave the menu and open the screen they mean.
- Don't call `present()` from a menu. It captures at once, so the capture is the menu.
- Show the entry only when `globalThis.__feedbackEngine` exists, so it is gone from a build that leaves Feedback out.

### Verify each screen

Do this after changing a screen, against the dev server, with realistic data:

1. Open the screen in Playwright and call `await page.evaluate(() => __feedbackEngine.present())`. Alt+Meta+click is the path a person takes: `await page.getByRole('heading').first().click({ modifiers: ['Alt', 'Meta'] })`.
2. Export the tree: add one item, then **Share › JSON**. The page holds the file: `await page.evaluate(() => __feedbackEngine.lastExport[0].blob.text())`.
3. [Replay every tap](#replay-every-tap) on the export.
4. Spot-check with real clicks on the regions you changed and read the selection title in the panel. The screenshot is scaled, so convert page points with the bounding box of the element with the role `img` and the name `Screenshot`.
5. Check both a development build and a production build if untagged elements matter: only a development build gives them a `file:line`.

## React

The app has `feedbackEngineReact()` in its Vite config, before the React plugin. That plugin is what finds the components and gives each one its name and `file:line`.

### Accessibility (do this first)

- Use the element that has the role: `<button>`, `<a href>`, `<input>`, `<select>`, `<h1>` to `<h6>`. A `<div onClick>` has no role, so it is not an element in a capture. If you must build a control from a `<div>`, give it its `role`.
- Give every icon-only button an `aria-label`, and every `<img>` an `alt`. An image with `alt=""` is decorative and left out.
- Hide decorative marks, such as a colored dot or an initials tile, with `aria-hidden="true"`.
- Name a field with a `<label>` around it or an `aria-label`. The capture reads the name and the value together, such as `Text field "Title, Bananas"`.
- A button or a link merges everything inside it into one element, such as `Link "Work 3"`. That is right for a row that reads as one sentence. A component inside it is still a node of its own.
- Landmarks, lists, and groups (`<main>`, `<nav>`, `<section>`, `<ul>`, `role="group"`) are walked through and never become nodes, even with a label. Make one the root element of a component, or tag it, when a tap on its padding should select it.
- A modal `<dialog>`, an open `popover`, and an `aria-modal="true"` dialog are layers of their own. Use one of them for anything that covers the page, including what you render through a portal, so taps on it select only what is inside it.

### Components

Every component of the app is in a capture already, under its own name, with its props and the `file:line` of its declaration. So the work is in how you write components, not in tagging them:

- Declare each component at the top level of a `.jsx` or `.tsx` module, with a capitalized name: a function, a class, an arrow function, or a `memo` or `forwardRef` call. A component declared inside another function, and one exported as `export default () => …` without a name, is not found.
- Make each region a person would point at its own component: a row, a card, a chart, a section with a visible frame. Extracting it is the React way to name it, and repeated rows then get the faint outline of the same part in their siblings.
- Give a component one root element with the box you mean. A component that renders several elements is one box around all of them, which is rarely the region a person points at.
- Name a component with the noun the user would say. An anonymous wrapper such as `Wrapper` or `Container` reads badly in a path.
- A component that only arranges others, such as `App` around the router or a provider, is harmless. It shares its box with what is inside it, which gets the taps.
- A library's components, such as a router's `Link` or a UI kit's `Button`, are not nodes. The elements they draw still are. Wrap one in a component of your own when it is a region.

### Tags

`feedback(name, data)` from `@smirea/feedback-engine/react` returns a ref.

- Tag a region drawn inline where it is drawn: `<figure ref={feedback('Chart', () => plot)}>`. Extracting the region into a component is just as good when it has its own inputs.
- Always give drawings that expose no elements a component or a tag: an `<svg>` chart, a `<canvas>`, a photo.
- To report state, tag the component's root element under the component's own name: `<dialog ref={feedback('TodoDetailDialog', () => ({ item: draft }))}>`. The tag's data replaces the props. Any other name makes a second node inside the component.
- On an element that already has a ref, call both from one ref function: `ref={node => { tag(node); inputRef.current = node; }}`, with `const tag = feedback('Name')` in the component's body.
- Don't tag an element with `display: contents`. It has no box.
- Don't tag a single text, button, image, or field. It's already an element.

### Data

- A component's data is its props. `children` and functions are left out, and a prop that is JSX reads as its tag, such as `<Icon>`.
- Hook state is not in a capture, because React keeps it without names. Report the state that explains what the screen shows, such as a filter, a draft, or the open item, with a tag under the component's name.
- Do the same when the props are too much, such as a component that receives a large list: `feedback('TodoList', () => ({ count: items.length }))`.
- The data function runs when a capture is taken, never while rendering, so it may read whatever the component has.
- A class shows under its own name, such as `TodoStore(lists: [...])`. Give it a `toFeedback()` method to choose what it reports.

### A way to open Feedback

- With a mouse, Alt+Meta+click on anything opens the editor with that element selected. There is nothing to build.
- A phone has no modifier keys, and a shake does not work on the web yet. Add an entry to a menu the app already has, such as Settings or an account menu, that starts a countdown: `<button onClick={() => globalThis.__feedbackEngine?.countdown()}>Send Feedback</button>`. The page shows a pill that counts down from 5 and then captures, so the person has time to leave the menu and open the screen they mean.
- Don't call `present()` from a menu. It captures at once, so the capture is the menu.
- Show the entry only when `globalThis.__feedbackEngine` exists, so it is gone from a build that leaves Feedback out.

### Verify each screen

Do this after changing a screen, against the dev server, with realistic data:

1. Open the screen in Playwright and call `await page.evaluate(() => __feedbackEngine.present())`. Alt+Meta+click is the path a person takes: `await page.getByRole('heading').first().click({ modifiers: ['Alt', 'Meta'] })`.
2. Export the tree: add one item, then **Share › JSON**. The page holds the file: `await page.evaluate(() => __feedbackEngine.lastExport[0].blob.text())`.
3. [Replay every tap](#replay-every-tap) on the export. Add `--wrapper App`, with the name of each component that wraps the whole app, so the screen's own component counts as the root.
4. Read the tree for what should not be there: a component named after a wrapper, the same name twice in one path, or a screen component missing because it was declared inside another function.
5. Spot-check with real clicks on the regions you changed and read the selection title in the panel. The screenshot is scaled, so convert page points with the bounding box of the element with the role `img` and the name `Screenshot`.
6. Check a production build once: components keep their names and locations there, and untagged elements lose their `file:line`.

## Replay every tap

`scripts/taps.py`, in this skill's folder, reads a `feedback.json` from any package. Without a local copy, stream it from GitHub:

```sh
gh api repos/smirea/feedback-engine/contents/skills/feedback-accessibility/scripts/taps.py \
  -H 'Accept: application/vnd.github.raw' | python3 - feedback.json
```

It mirrors Feedback's hit testing on an 8 pt grid and prints the share of taps that fall through to a screen or layer root, the bands where most of a row falls through, and the elements that sit directly under a root. Every band should be a margin, a gap, or empty space, and every listed element should be a precise target on its own, such as a lone button. Anything else is a missing tag or, in React, a region that should be its own component. This covers the parts of a long screen that the editor canvas doesn't show without scrolling.
