# Features

This table lists what Feedback does and where each platform stands. [`report.md`](report.md) defines the export format. This file defines the behavior around it.

Each row has one status per platform.

- `shipped`: the platform does it, and the notes say how when the mechanism is not obvious.
- `planned`: the platform will do it. The notes say how, and what differs from the other platform.
- `no`: the platform will not do it. The notes say why.

Add or update a row in the same change that adds, changes, or removes behavior on any platform. A new row needs a status for every platform, so a feature cannot land on one platform without a decision about the others. `bun test spec` checks that every row has a unique id and a valid status, and that every `no` has a reason.

## Trigger

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| T1 | One call at launch turns Feedback on. | shipped | shipped | iOS: `Feedback.enable()`. Web: `setupFeedbackEngine()` from `@smirea/feedback-engine/svelte`. On a server it returns an engine that does nothing. |
| T2 | A deliberate gesture shows an **Add Feedback** pill at the top center. Tapping the pill captures the screen and opens the editor. | shipped | shipped | iOS: a shake. Web: a keyboard shortcut, `Alt+Shift+F` unless the app sets another, because a desktop has no shake. |
| T3 | The pill morphs out of a capsule the size of the Dynamic Island. | shipped | no | A browser has no Dynamic Island. The web pill drops in at the top center. |
| T4 | The pill leaves by itself after 5 seconds. Triggering again restarts the timer. | shipped | shipped | |
| T5 | Leaving the app or locking the phone clears the pill at once. | shipped | shipped | Web: on `visibilitychange`. |
| T6 | The app can open the editor from its own control. | shipped | shipped | iOS: `Feedback.present()`. Web: `present()` on the object `setupFeedbackEngine()` returns. |
| T7 | The app can keep Feedback out of production builds. | shipped | shipped | iOS: wrap `enable()` in `#if DEBUG`. Web: call `setupFeedbackEngine()` behind `import.meta.env.DEV` with a dynamic import. The production bundle then has the tags and none of the editor. |
| T8 | On a phone, a shake is the gesture. | shipped | planned | Web: needs the `devicemotion` permission, which iOS Safari grants only from a tap. Not built, because it cannot be checked without a physical phone. A phone uses the app's own control (T6) until then. |

## Tagging

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| G1 | One call at the end of a component names it after its type and reports its data. | shipped | shipped | iOS: `.feedback(self)`. Web: `{@attach feedback()}` on the component's root element. The Vite plugin names it after the file. |
| G2 | The app can choose the name and the data. | shipped | shipped | iOS: `.feedback("TodoRow", data: item)`. Web: `{@attach feedback('TodoRow', () => item)}`. The data function runs when a capture is taken. |
| G3 | A component reports the `file:line` of its tag call. | shipped | shipped | iOS: `#fileID` and `#line`. Web: JavaScript has neither, so the Vite plugin writes the location into each `feedback(` call at build time. |
| G4 | A design-system container can report its caller's `file:line` instead of its own. | shipped | planned | iOS: `file:` and `line:` parameters. Web: the plugin would have to pass each caller's location to the container. |
| G5 | Component nesting follows the real hierarchy. | shipped | shipped | iOS: each tag passes its id down the SwiftUI environment. Web: DOM ancestry. |
| G6 | Tagging costs nothing per frame. | shipped | shipped | iOS: a plain `UIView` behind the tagged view, found by walking the hierarchy at capture time. Web: one `WeakMap` entry per tagged element. |
| G7 | A type can choose how it reads in component data. | shipped | shipped | iOS: `FeedbackRepresentable`. Web: a `toFeedback()` method. |
| G8 | Component data is read without the app listing it. | shipped | shipped | iOS: reflection over the view's stored properties, `@State`, `@Binding`, and `@Bindable`. Web: for a `feedback()` call without arguments, the Vite plugin passes the component's props and its `$state` variables. |
| G9 | Untagged controls and text still appear, as elements from the accessibility tree. | shipped | shipped | iOS: `UIAccessibility` elements. Web: DOM elements with a control's ARIA role or their own text. |
| G10 | Every element reports its own `file:line`, tagged or not. | no | shipped | iOS: SwiftUI exposes no source location at runtime. Web: Svelte records it on every element in development builds only. |

## Component data

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| D1 | Data is one `label: value` line per property, or the description of the value the app passed. | shipped | shipped | |
| D2 | Floating-point numbers keep 3 decimals, or 3 significant digits below 1. | shipped | shipped | |
| D3 | Structured values read like code. | shipped | shipped | iOS: `Entry(kg: 72.575, note: nil)`. Web: class instances the same way, plain objects as `{kg: 72.575, note: null}`. A minified build shows a class's minified name. |
| D4 | Nesting stops after 3 levels, lists after 10 elements, and a component's data after 1,500 characters. | shipped | shipped | |
| D5 | Functions and framework internals are left out at any depth. | shipped | shipped | iOS: closures, SwiftUI, and Combine types. Web: functions and DOM nodes. A class's `$state` fields read as their values. |
| D6 | A value with its own text description uses it. | shipped | shipped | iOS: `CustomStringConvertible`, such as `Date` and `UUID`. Web: `Date` as ISO 8601, and `toFeedback()`. |

## Capture

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| C1 | The screenshot and the tree are read at the moment of the trigger. | shipped | shipped | iOS: `drawHierarchy`. Web: the DOM drawn again into a canvas, because the browser gives a page no screenshot call without a permission prompt. |
| C2 | A screen with a long main scroll view is captured at full length. | shipped | shipped | iOS: scrolls one screen at a time and stitches. Web: the document is drawn at its full scroll height in one pass. |
| C3 | Bars above the content stay at the top of a full-length capture, and bars below it move to the bottom. | shipped | no | Web: a `position: fixed` bar is drawn where it was on screen, over the visible part of the capture. That is what the user saw, and it needs no guess about which edge a bar belongs to. A sticky bar is drawn at its place in the document. |
| C4 | A sheet expanded to full height is captured at full length. | shipped | no | Web: a dialog that scrolls inside itself shows what was on screen. Revisit if an app needs it. |
| C5 | Only the largest vertical scroll view is captured at full length. Others show what was on screen. | shipped | shipped | Web: the document scroll is full length. An inner `overflow` container shows what was on screen, with frames clipped to it. |
| C6 | A full-length capture stops at a height limit and ends between two rows. | shipped | no | Web: a tall page is drawn whole at a lower scale, so the capture fits a 16 megapixel canvas, the limit of iOS Safari. |
| C7 | Presented layers are separate. A tap on a layer selects only what is inside it, and content a layer hides completely is left out. | shipped | shipped | iOS: sheets, popovers, alerts, covers, and menus. Web: modal `<dialog>` elements, open popovers, and `aria-modal` dialogs. |
| C8 | The keyboard is drawn as a gray block, and taps there select the keyboard. | shipped | no | Web: a desktop has no on-screen keyboard, and a phone's keyboard is not in the DOM. |
| C9 | Accessibility elements are switched on for the capture and restored after. | shipped | no | Web: the DOM always carries roles and names. |
| C10 | The capture records the environment. | shipped | shipped | iOS: app, location, version, device, display, time, and locale. Web: app name and version from `setupFeedbackEngine()`, the URL's path, the browser and platform, the viewport with its pixel ratio and color scheme, time, and locale. |
| C11 | The capture records a screen name. | shipped | shipped | iOS: the topmost navigation title, or the selected tab's. Web: `document.title`. |
| C12 | The app attaches its own state to every capture. | shipped | shipped | iOS: `Feedback.context(name) { value }`. Web: `context(name, () => value)`. The function runs when a capture is taken. |
| C13 | Rows that a lazy container has not created are missing. | shipped | shipped | The same limit holds for virtualized lists on the web. |
| C14 | Scrolling during a capture is real, so code that reacts to it runs. | shipped | shipped | Web: the window jumps to its origin and back inside one task, so nothing is painted, and scroll listeners run. |
| C15 | A modal's dimmed backdrop and the state of form fields are in the screenshot. | shipped | shipped | iOS: they are pixels like any other. Web: a re-draw of the DOM loses both, so the capture paints the backdrop and writes each field's state into the copy. A placeholder is drawn in the field's text color. |

## Tree

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| R1 | Nodes are numbered depth-first in reading order, so a parent has a lower number than its children. | shipped | shipped | Web: `buildTree` in the TypeScript core. |
| R2 | An element's parent is the smallest component that holds its centre and three quarters of its area, or else the smallest that holds its centre. | shipped | shipped | Web: DOM ancestry gives the parent directly. |
| R3 | Hit-testing picks the smallest node under the point, on the topmost layer that covers it. | shipped | shipped | |
| R4 | A tagged component inside a button or link is a child of that button or link. | shipped | shipped | Web: true by DOM ancestry. |
| R5 | The same part in sibling components is found, such as the same button in every row. | shipped | shipped | |
| R6 | Frames are clipped to the capture. | shipped | shipped | |
| R7 | A button, a link, or a switch is one element with its content merged into its label, so the text inside it cannot be picked by itself. A tagged component inside it still can. | shipped | shipped | iOS: the accessibility tree merges them. Web: an untagged descendant of an element with a control's role is not a node. |
| R8 | Only leaf elements become nodes. A container is walked through, even when it has a label. | shipped | shipped | Web: landmark, list, and group roles are walked through. A text that wraps a control, such as a label around its field, is the control's parent. |

## Editor

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| E1 | The editor shows the frozen screenshot. A tap selects the most specific node under it. | shipped | shipped | |
| E2 | The same part in sibling components is outlined faintly. | shipped | shipped | |
| E3 | The screenshot scrolls to reach content that was off screen, and zooms up to 4×, also while typing. | shipped | shipped | iOS: pinch. Web: Ctrl with the wheel, which is also what a trackpad pinch sends. A touch-screen pinch is written and not tested, because Playwright cannot pinch. |
| E4 | The selection sits between its parent and its child. Tapping either moves the selection. | shipped | shipped | |
| E5 | The user types feedback and submits it. Each item gets a numbered box. | shipped | shipped | Web: Enter submits, and Shift with Enter adds a line. |
| E6 | A tap inside a numbered box brings back that item's feedback for editing. A second tap drills down. | shipped | shipped | |
| E7 | Feedback belongs to one level of the hierarchy. | shipped | shipped | |
| E8 | A list shows the items, lets the user remove them, and shows the context that will be attached. | shipped | shipped | |
| E9 | Closing asks first when items were never shared, and gives focus back to the field that had it. | shipped | shipped | |
| E10 | A draft survives a visit to a target that already has feedback. | shipped | shipped | |
| E11 | While the editor is open, assistive technology and UI automation see only the editor. | shipped | shipped | iOS: hides the app's windows from accessibility. Web: a modal dialog in the top layer makes the page inert. |
| E12 | The editor's text stops growing at the largest standard text size. | shipped | no | Web: browsers zoom the whole page, so the screenshot scales with the text. |
| E13 | Hovering shows which node a click would select. | no | shipped | iOS: a touch screen has no hover. |
| E14 | Typing `@` in the feedback text references another element. A tap picks it, arrows move to its parent or child, and **Insert** writes a token such as `@1_Dialog`. | shipped | shipped | |
| E15 | A referenced element keeps its number for the whole capture, and its box gets an `@N` tag. | shipped | shipped | |
| E16 | The screenshot's scale stays fixed while the panel under it grows. | shipped | shipped | |
| E17 | The editor's styles and the app's styles do not reach each other. | shipped | shipped | iOS: a separate window. Web: a shadow root. |

## Export and sharing

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| X1 | The image export is one `feedback.png` with numbered boxes, a card per item, and the environment. | shipped | shipped | Web: drawn on a canvas with the layout rules of `report.md`. |
| X2 | The JSON export is one `feedback.json` with the items, the tree, the component data, and the context. | shipped | shipped | |
| X3 | Image and JSON export together as one `feedback.zip`. | shipped | shipped | |
| X4 | **Copy Feedback** puts the image export on the clipboard as one PNG. | shipped | shipped | Web: `navigator.clipboard.write`, in a secure context. |
| X5 | **Copy Feedback** puts the JSON export on the clipboard as JSON and plain text. | shipped | shipped | Web: plain text only, the one text type browsers accept. |
| X6 | **Copy Feedback** for the ZIP puts both the image and the JSON on the clipboard, as two items. | shipped | shipped | Web: browsers accept one clipboard item per write. The web writes one item with a PNG and a plain-text representation, and the paste target picks one. |
| X7 | The export goes to any system share target, such as Messages, Notes, or Files. | shipped | shipped | Web: **Save File** downloads it. **Share…** shows where the browser has `navigator.share` for files, and is not tested, because a headless browser has none. |
| X8 | Each export is written to a file an agent can read without the share sheet. | shipped | shipped | iOS: `tmp/feedback.*` in the app's container. Web: `__feedbackEngine.lastExport` on the page holds the files. |
| X9 | An item counts as shared once a share completes. | shipped | shipped | |
| X10 | The exports carry the references. The image draws a box for each referenced node and highlights each token in its color. The JSON lists them under `references`. | shipped | shipped | |

## ProcrastiMate

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| P1 | The Share menu posts the feedback to ProcrastiMate as one task. | shipped | shipped | Web: through the dev server. ProcrastiMate's API sends no CORS headers, so `feedbackProcrastimate()` from `@smirea/feedback-engine/vite` forwards the page's calls and adds the token there. A deployed static site has no such server and no ProcrastiMate entry. |
| P2 | The post uses the session ProcrastiMate shares with the team's other apps. | shipped | no | iOS: the shared keychain group. Web: browsers share no storage across origins. The dev server holds a token instead, from its own environment. |
| P3 | A picker lists projects with their icons and sections, with the last project already selected. | shipped | shipped | Web: without the icons, which are SF Symbols on iOS. |
| P4 | The task name starts as the screen's name, `Feedback`, and the item count. | shipped | shipped | |
| P5 | An on-device language model summarizes the items into the task name without blocking the post. | shipped | planned | iOS: Apple Intelligence. Web: Chrome's built-in model. Not built, because Chrome reports the model as unavailable on the machine this was developed on, so it could not be checked. |
| P6 | The task carries the image export as JPEG with a thumbnail, and `feedback.json`. | shipped | shipped | |
| P7 | A toast confirms the post and opens the task when tapped. | shipped | shipped | iOS: `procrastimate://task/<id>`. Web: the task's page in the ProcrastiMate web app. |

## Agent workflow

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| A1 | A skill tells an app's agents how to make screens accessible and precise to point at. | shipped | shipped | `skills/feedback-accessibility` has a section for SwiftUI and one for Svelte. |
| A2 | A script replays every tap on an exported tree and reports the taps that fall through. | shipped | shipped | `skills/feedback-accessibility/scripts/taps.py` reads `feedback.json`, so it runs on a web export unchanged. |
| A3 | An example app with every screen tagged is there to try Feedback on. | shipped | shipped | iOS: `examples/todo-ios`. It is not in ProcrastiMate's keychain group, so a post needs another app. Web: `examples/todo-svelte`. |
| A4 | An agent can trigger a capture and read the export without a person. | shipped | shipped | iOS: `simctl` shake and the app's container. Web: `__feedbackEngine.present()` and `__feedbackEngine.lastExport` from Playwright. |
