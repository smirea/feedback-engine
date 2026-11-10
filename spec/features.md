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
| T1 | One call at launch turns Feedback on. | shipped | planned | iOS: `Feedback.enable()`. Web: `setupFeedbackEngine()` from `@smirea/feedback-engine/svelte`, called in the browser only. |
| T2 | A deliberate gesture shows an **Add Feedback** pill at the top center. Tapping the pill captures the screen and opens the editor. | shipped | planned | iOS: a shake. Web: a keyboard shortcut, because a desktop has no shake. A shake on phones needs the `devicemotion` permission, which iOS Safari grants only from a tap. |
| T3 | The pill morphs out of a capsule the size of the Dynamic Island. | shipped | no | A browser has no Dynamic Island. The web pill fades in at the top center. |
| T4 | The pill leaves by itself after 5 seconds. Triggering again restarts the timer. | shipped | planned | |
| T5 | Leaving the app or locking the phone clears the pill at once. | shipped | planned | Web: on `visibilitychange`. |
| T6 | The app can open the editor from its own control. | shipped | planned | iOS: `Feedback.present()`. Web: `present()` on the object `setupFeedbackEngine()` returns. |
| T7 | The app can keep Feedback out of production builds. | shipped | planned | iOS: wrap `enable()` in `#if DEBUG`. Web: call `setupFeedbackEngine()` behind `import.meta.env.DEV` with a dynamic import, so the production bundle drops the package. |

## Tagging

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| G1 | One call at the end of a component names it after its type and reports its data. | shipped | planned | iOS: `.feedback(self)` reads stored properties, `@State`, `@Binding`, and `@Bindable`. Web: `{@attach feedback()}` on the component's root element. The Vite plugin names it after the file. Data is explicit on web until G8 is settled. |
| G2 | The app can choose the name and the data. | shipped | planned | iOS: `.feedback("TodoRow", data: item)`. Web: `{@attach feedback('TodoRow', () => item)}`. The data function runs when a capture is taken. |
| G3 | A component reports the `file:line` of its tag call. | shipped | planned | iOS: `#fileID` and `#line`. Web: JavaScript has neither, so the Vite plugin writes the location into each `feedback(` call at build time. |
| G4 | A design-system container can report its caller's `file:line` instead of its own. | shipped | planned | iOS: `file:` and `line:` parameters. Web: a `source` option on `feedback()`. |
| G5 | Component nesting follows the real hierarchy. | shipped | planned | iOS: each tag passes its id down the SwiftUI environment. Web: DOM ancestry. |
| G6 | Tagging costs nothing per frame. | shipped | planned | iOS: a plain `UIView` behind the tagged view, found by walking the hierarchy at capture time. Web: one `WeakMap` entry per tagged element. |
| G7 | A type can choose how it reads in component data. | shipped | planned | iOS: `FeedbackRepresentable`. Web: a `toFeedback()` method. |
| G8 | Component data is read without the app listing it. | shipped | planned | iOS: reflection over the view. Web: the Vite plugin can pass the component's declared props. Unproven. |
| G9 | Untagged controls and text still appear, as elements from the accessibility tree. | shipped | planned | iOS: `UIAccessibility` elements. Web: DOM elements with an ARIA role or their own text. |
| G10 | Every element reports its own `file:line`, tagged or not. | no | planned | iOS: SwiftUI exposes no source location at runtime. Web: Svelte records it on every element in development builds only. |

## Component data

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| D1 | Data is one `label: value` line per property, or the description of the value the app passed. | shipped | planned | |
| D2 | Floating-point numbers keep 3 decimals, or 3 significant digits below 1. | shipped | planned | |
| D3 | Structured values read like code. | shipped | planned | iOS: `Entry(kg: 72.575, note: nil)`. Web: class instances the same way, plain objects as `{kg: 72.575, note: null}`. `report.md` needs a section for JavaScript values. |
| D4 | Nesting stops after 3 levels, lists after 10 elements, and a component's data after 1,500 characters. | shipped | planned | |
| D5 | Functions and framework internals are left out at any depth. | shipped | planned | iOS: closures, SwiftUI, and Combine types. Web: functions, DOM nodes, and Svelte internals. `$state` proxies read as their values. |
| D6 | A value with its own text description uses it. | shipped | planned | iOS: `CustomStringConvertible`, such as `Date` and `UUID`. Web: `Date` as ISO 8601, and `toFeedback()`. |

## Capture

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| C1 | The screenshot and the tree are read at the moment of the trigger. | shipped | planned | iOS: `drawHierarchy`. Web: the DOM rendered to a canvas. The browser gives a page no screenshot call without a permission prompt. |
| C2 | A screen with a long main scroll view is captured at full length. | shipped | planned | iOS: scrolls one screen at a time and stitches. Web: the document renders at its full scroll height in one pass, without scrolling. |
| C3 | Bars above the content stay at the top of a full-length capture, and bars below it move to the bottom. | shipped | planned | Web: `position: fixed` and `sticky` elements need their frames mapped the same way. Unproven. |
| C4 | A sheet expanded to full height is captured at full length. | shipped | no | Web: a dialog that scrolls inside itself shows what was on screen. Revisit if an app needs it. |
| C5 | Only the largest vertical scroll view is captured at full length. Others show what was on screen. | shipped | planned | Web: the document scroll is full length. An inner `overflow` container shows what was on screen. |
| C6 | A full-length capture stops at a height limit and ends between two rows. | shipped | planned | iOS: 16,000 pixels. Web: the canvas limit of the browser, which is lowest on iOS Safari. |
| C7 | Presented layers are separate. A tap on a layer selects only what is inside it, and content a layer hides completely is left out. | shipped | planned | iOS: sheets, popovers, alerts, covers, and menus. Web: modal `<dialog>` elements, open popovers, and `aria-modal` dialogs. |
| C8 | The keyboard is drawn as a gray block, and taps there select the keyboard. | shipped | no | Web: a desktop has no on-screen keyboard, and a phone's keyboard is not in the DOM. |
| C9 | Accessibility elements are switched on for the capture and restored after. | shipped | no | Web: the DOM always carries roles and names. |
| C10 | The capture records the environment. | shipped | planned | iOS: app, location, version, device, display, time, and locale. Web: app name and version from `setupFeedbackEngine()`, the URL, the browser and platform, the viewport with its pixel ratio and color scheme, time, and locale. |
| C11 | The capture records a screen name. | shipped | planned | iOS: the topmost navigation title, or the selected tab's. Web: `document.title`. |
| C12 | The app attaches its own state to every capture. | shipped | planned | iOS: `Feedback.context(name) { value }`. Web: `context(name, () => value)`. The function runs when a capture is taken. |
| C13 | Rows that a lazy container has not created are missing. | shipped | planned | The same limit holds for virtualized lists on the web. |
| C14 | Scrolling during a capture is real, so code that reacts to it runs. | shipped | no | Web: a capture does not scroll. |

## Tree

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| R1 | Nodes are numbered depth-first in reading order, so a parent has a lower number than its children. | shipped | planned | Web: the TypeScript core ports `TreeBuilder`. |
| R2 | An element's parent is the smallest component that holds its centre and three quarters of its area, or else the smallest that holds its centre. | shipped | planned | Web: DOM ancestry gives the parent directly. `report.md` needs to say that a real hierarchy wins over geometry. |
| R3 | Hit-testing picks the smallest node under the point, on the topmost layer that covers it. | shipped | planned | |
| R4 | A tagged component inside a button or link is a child of that button or link. | shipped | planned | Web: true by DOM ancestry. |
| R5 | The same part in sibling components is found, such as the same button in every row. | shipped | planned | Web: the TypeScript core ports `Capture.similar`. |
| R6 | Frames are clipped to the capture. | shipped | planned | |
| R7 | A button, a link, or a switch is one element with its content merged into its label, so the text inside it cannot be picked by itself. A tagged component inside it still can. | shipped | planned | iOS: the accessibility tree merges them. Web: an untagged descendant of an element with the role button, link, or switch is not a node. |
| R8 | Only leaf elements become nodes. A container is walked through, even when it has a label. | shipped | planned | Web: landmark, list, and group roles are walked through. |

## Editor

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| E1 | The editor shows the frozen screenshot. A tap selects the most specific node under it. | shipped | planned | |
| E2 | The same part in sibling components is outlined faintly. | shipped | planned | |
| E3 | The screenshot scrolls to reach content that was off screen, and zooms up to 4×, also while typing. | shipped | planned | iOS: pinch. Web: pinch on touch screens and trackpads, and Ctrl with the wheel. |
| E4 | The selection sits between its parent and its child. Tapping either moves the selection. | shipped | planned | |
| E5 | The user types feedback and submits it. Each item gets a numbered box. | shipped | planned | |
| E6 | A tap inside a numbered box brings back that item's feedback for editing. A second tap drills down. | shipped | planned | |
| E7 | Feedback belongs to one level of the hierarchy. | shipped | planned | |
| E8 | A list shows the items, lets the user remove them, and shows the context that will be attached. | shipped | planned | |
| E9 | Closing asks first when items were never shared, and gives focus back to the field that had it. | shipped | planned | |
| E10 | A draft survives a visit to a target that already has feedback. | shipped | planned | Web: the TypeScript core ports `Session`. |
| E11 | While the editor is open, assistive technology and UI automation see only the editor. | shipped | planned | iOS: hides the app's windows from accessibility. Web: a modal dialog in the top layer makes the page inert. |
| E12 | The editor's text stops growing at the largest standard text size. | shipped | no | Web: browsers zoom the whole page, so the screenshot scales with the text. |
| E13 | Hovering shows which node a click would select. | no | planned | iOS: a touch screen has no hover. |
| E14 | Typing `@` in the feedback text references another element. A tap picks it, arrows move to its parent or child, and **Insert** writes a token such as `@1_Dialog`. | shipped | planned | Web: the TypeScript core ports the reference rules of `Session`. |
| E15 | A referenced element keeps its number for the whole capture, and its box gets an `@N` tag. | shipped | planned | |

## Export and sharing

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| X1 | The image export is one `feedback.png` with numbered boxes, a card per item, and the environment. | shipped | planned | Web: drawn on a canvas with the layout rules of `report.md`. |
| X2 | The JSON export is one `feedback.json` with the items, the tree, the component data, and the context. | shipped | planned | |
| X3 | Image and JSON export together as one `feedback.zip`. | shipped | planned | Web: needs a ZIP writer. |
| X4 | **Copy Feedback** puts the image export on the clipboard as one PNG. | shipped | planned | Web: `navigator.clipboard.write`, in a secure context. |
| X5 | **Copy Feedback** puts the JSON export on the clipboard as JSON and plain text. | shipped | planned | |
| X6 | **Copy Feedback** for the ZIP puts both the image and the JSON on the clipboard, as two items. | shipped | planned | Web: browsers accept one clipboard item per write. The web writes one item with a PNG and a plain-text representation, and the paste target picks one. `report.md` needs to say so. |
| X7 | The export goes to any system share target, such as Messages, Notes, or Files. | shipped | planned | Web: `navigator.share` with files where the browser has it, and a file download elsewhere. |
| X8 | Each export is written to a file an agent can read without the share sheet. | shipped | planned | iOS: `tmp/feedback.*` in the app's container. Web: the last export is readable from the page, for Playwright. |
| X9 | An item counts as shared once a share completes. | shipped | planned | |
| X10 | The exports carry the references. The image draws a box for each referenced node and highlights each token in its color. The JSON lists them under `references`. | shipped | planned | |

## ProcrastiMate

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| P1 | The Share menu posts the feedback to ProcrastiMate as one task. | shipped | planned | Web: blocked. ProcrastiMate's API sends no CORS headers, so a page on another origin cannot call it. |
| P2 | The post uses the session ProcrastiMate shares with the team's other apps. | shipped | no | iOS: the shared keychain group. Web: browsers share no storage across origins. The web needs a token from the app or a ProcrastiMate sign-in window. |
| P3 | A picker lists projects with their icons and sections, with the last project already selected. | shipped | planned | |
| P4 | The task name starts as the screen's name, `Feedback`, and the item count. | shipped | planned | |
| P5 | An on-device language model summarizes the items into the task name without blocking the post. | shipped | planned | iOS: Apple Intelligence. Web: Chrome's built-in model where the browser has one. Other browsers keep the first name. |
| P6 | The task carries the image export as JPEG with a thumbnail, and `feedback.json`. | shipped | planned | |
| P7 | A toast confirms the post and opens the task when tapped. | shipped | planned | iOS: `procrastimate://task/<id>`. Web: the task's page in the ProcrastiMate web app. |

## Agent workflow

| ID | Feature | iOS | Web | Notes |
| --- | --- | --- | --- | --- |
| A1 | A skill tells an app's agents how to make screens accessible and precise to point at. | shipped | planned | iOS: `skills/feedback-accessibility`, written for SwiftUI. Web: the same rule and the same checks, with a section for Svelte and ARIA. |
| A2 | A script replays every tap on an exported tree and reports the taps that fall through. | shipped | planned | `skills/feedback-accessibility/scripts/taps.py` reads `feedback.json`, so it runs on a web export unchanged once the web exports one. |
| A3 | An example app with every screen tagged is there to try Feedback on. | shipped | planned | iOS: `examples/todo-ios`. It is not in ProcrastiMate's keychain group, so a post needs another app. Web: `examples/todo-svelte`, which has the Lists screen so far. |
| A4 | An agent can trigger a capture and read the export without a person. | shipped | planned | iOS: `simctl` shake and the app's container. Web: Playwright presses the shortcut and reads the export from the page. |
