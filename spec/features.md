# Features

This table lists what Feedback does and where each platform stands. Svelte and React are the two entry points of the web package. They share the capture, the tree, the editor, and the exports, so a note that starts with `Web:` holds for both. [`report.md`](report.md) defines the export format. This file defines the behavior around it.

Each row has one status per platform.

- `shipped`: the platform does it, and the notes say how when the mechanism is not obvious.
- `planned`: the platform will do it. The notes say how, and what differs from the other platforms.
- `no`: the platform will not do it. The notes say why.

Add or update a row in the same change that adds, changes, or removes behavior on any platform. A new row needs a status for every platform, so a feature cannot land on one platform without a decision about the others. `bun test spec` checks that every row has a unique id and a valid status, and that every `no` has a reason.

## Trigger

| ID | Feature | iOS | Svelte | React | Notes |
| --- | --- | --- | --- | --- | --- |
| T1 | One call at launch turns Feedback on. | shipped | shipped | shipped | iOS: `Feedback.enable()`. Web: `setupFeedbackEngine()` from `@smirea/feedback-engine/svelte` or `/react`. On a server it returns an engine that does nothing. |
| T2 | A deliberate gesture shows an **Add Feedback** pill at the top center. Tapping the pill captures the screen and opens the editor. | shipped | shipped | shipped | iOS: a shake. Web: the default gesture is a click and needs no pill (T10). A keyboard chord, such as `shortcut: 'Alt+Shift+F'`, shows the pill, and so does `showPill()`. |
| T3 | The pill morphs out of a capsule the size of the Dynamic Island. | shipped | no | no | A browser has no Dynamic Island. The web pill drops in at the top center. |
| T4 | The pill leaves by itself after 5 seconds. Triggering again restarts the timer. | shipped | shipped | shipped | |
| T5 | Leaving the app or locking the phone clears the pill at once. | shipped | shipped | shipped | Web: on `visibilitychange`. |
| T6 | The app can open the editor from its own control. | shipped | shipped | shipped | iOS: `Feedback.present()`. Web: `present()` on the object `setupFeedbackEngine()` returns. |
| T7 | The app can keep Feedback out of production builds. | shipped | shipped | shipped | iOS: wrap `enable()` in `#if DEBUG`. Web: call `setupFeedbackEngine()` behind `import.meta.env.DEV` with a dynamic import. The production bundle then has the tags, or React's component names, and none of the editor. |
| T8 | On a phone, a shake is the gesture. | shipped | planned | planned | Web: needs the `devicemotion` permission, which iOS Safari grants only from a tap. Not built, because it cannot be checked without a physical phone. A phone uses a countdown from one of the app's menus (T9) until then. |
| T9 | A trigger in one of the app's menus starts a 5 second countdown, so the user can reach the screen they mean before the capture. | no | shipped | shipped | iOS: a shake works on every screen, so no trigger has to live in a menu. Web: `countdown()`. The pill shows **Feedback in 5** and counts down, then captures. Pressing the pill captures at once. It is the trigger for a phone, which has no modifier keys. |
| T10 | Pointing at something opens the editor with it selected. | no | shipped | shipped | iOS: a shake has no position. Web: Alt+Meta+click, or the chord in `shortcut` when it ends in `Click`. The app does not get the click, and a disabled control can be clicked, because the trigger is the pointer's release. |
| T11 | A round Feedback button on every screen captures it when tapped. It can be dragged to another height or side, and stays there. | no | shipped | shipped | iOS: a shake works on every screen. Web: `setupFeedbackEngine({ button: true })`, for a phone or an app opened from the home screen, which have no keyboard. Its place is kept in `localStorage`. It hides while the editor is open, and the capture leaves it out. |

## Tagging

| ID | Feature | iOS | Svelte | React | Notes |
| --- | --- | --- | --- | --- | --- |
| G1 | One call at the end of a component names it after its type and reports its data. | shipped | shipped | shipped | iOS: `.feedback(self)`. Svelte: `{@attach feedback()}` on the component's root element. The Vite plugin names it after the file. React: no call. See G11. |
| G2 | The app can choose the name and the data. | shipped | shipped | shipped | iOS: `.feedback("TodoRow", data: item)`. Svelte: `{@attach feedback('TodoRow', () => item)}`. React: `ref={feedback('TodoRow', () => item)}`. The data function runs when a capture is taken. In React, a tag on a component's root element under the component's own name replaces that component's data. |
| G3 | A component reports the `file:line` of its tag call. | shipped | shipped | shipped | iOS: `#fileID` and `#line`. Web: JavaScript has neither, so the Vite plugin writes the location into each `feedback(` call at build time. A React component that is found without a tag reports the line of its declaration. |
| G4 | A design-system container can report its caller's `file:line` instead of its own. | shipped | planned | planned | iOS: `file:` and `line:` parameters. Web: the plugin would have to pass each caller's location to the container. |
| G5 | Component nesting follows the real hierarchy. | shipped | shipped | shipped | iOS: each tag passes its id down the SwiftUI environment. Web: DOM ancestry. React: its own component tree for the components, so a component that draws through a portal sits where it draws. |
| G6 | Tagging costs nothing per frame. | shipped | shipped | shipped | iOS: a plain `UIView` behind the tagged view, found by walking the hierarchy at capture time. Web: one `WeakMap` entry per tagged element. React: one entry per component, written when its module loads, and the component tree is read only when a capture is taken. |
| G7 | A type can choose how it reads in component data. | shipped | shipped | shipped | iOS: `FeedbackRepresentable`. Web: a `toFeedback()` method. |
| G8 | Component data is read without the app listing it. | shipped | shipped | shipped | iOS: reflection over the view's stored properties, `@State`, `@Binding`, and `@Bindable`. Svelte: for a `feedback()` call without arguments, the Vite plugin passes the component's props and its `$state` variables. React: the props, read from React's component tree. Hook state has no names at runtime, so a tag reports it (G2). |
| G9 | Untagged controls and text still appear, as elements from the accessibility tree. | shipped | shipped | shipped | iOS: `UIAccessibility` elements. Web: DOM elements with a control's ARIA role or their own text. |
| G10 | Every element reports its own `file:line`, tagged or not. | no | shipped | shipped | iOS: SwiftUI exposes no source location at runtime. Development builds only. Svelte records it on every element. React 19 no longer does, so the Vite plugin or the Next.js config writes it into a `data-feedback-source` attribute on the dev server. `elementSources: false` turns that off, and `elementSources: true` keeps it in a production build, for a deployed preview. |
| G11 | The app's components are in the capture without a tag, under their own names. | no | no | shipped | iOS: SwiftUI exposes no view hierarchy at runtime. Svelte: a compiled component leaves no record of itself in the page. React keeps a component tree, which a capture reads. The Vite plugin registers each component of the app with its name and `file:line`, because a minified build renames the functions React knows them by. Being registered also tells the app's components from a library's, which stay out of the tree. |
| G12 | A React app built with Next.js gets the same capture as one built with Vite. | no | no | shipped | iOS: not a web app. Svelte: SvelteKit builds with Vite. React: `withFeedbackEngine()` from `@smirea/feedback-engine/next` gives Turbopack and webpack one loader, which registers the components and compiles the editor. A server component leaves no component in the page, so only the elements it draws are nodes. |

## Component data

| ID | Feature | iOS | Svelte | React | Notes |
| --- | --- | --- | --- | --- | --- |
| D1 | Data is one `label: value` line per property, or the description of the value the app passed. | shipped | shipped | shipped | |
| D2 | Floating-point numbers keep 3 decimals, or 3 significant digits below 1. | shipped | shipped | shipped | |
| D3 | Structured values read like code. | shipped | shipped | shipped | iOS: `Entry(kg: 72.575, note: nil)`. Web: class instances the same way, plain objects as `{kg: 72.575, note: null}`. A minified build shows a class's minified name. |
| D4 | Nesting stops after 3 levels, lists after 10 elements, and a component's data after 1,500 characters. | shipped | shipped | shipped | |
| D5 | Functions and framework internals are left out at any depth. | shipped | shipped | shipped | iOS: closures, SwiftUI, and Combine types. Web: functions and DOM nodes. A class's `$state` fields read as their values. React: `children` is left out of a component's props, and a prop that is JSX reads as its tag, such as `<Icon>`. |
| D6 | A value with its own text description uses it. | shipped | shipped | shipped | iOS: `CustomStringConvertible`, such as `Date` and `UUID`. Web: `Date` as ISO 8601, and `toFeedback()`. |

## Capture

| ID | Feature | iOS | Svelte | React | Notes |
| --- | --- | --- | --- | --- | --- |
| C1 | The screenshot and the tree are read at the moment of the trigger. | shipped | shipped | shipped | iOS: `drawHierarchy`. Web: the DOM drawn again into a canvas, because the browser gives a page no screenshot call without a permission prompt. |
| C2 | A screen with a long main scroll view is captured at full length. | shipped | shipped | shipped | iOS: scrolls one screen at a time and stitches. Web: the document is drawn at its full scroll height in one pass. |
| C3 | Bars above the content stay at the top of a full-length capture, and bars below it move to the bottom. | shipped | no | no | Web: a `position: fixed` bar is drawn where it was on screen, over the visible part of the capture. That is what the user saw, and it needs no guess about which edge a bar belongs to. A sticky bar is drawn at its place in the document. |
| C4 | A sheet expanded to full height is captured at full length. | shipped | no | no | Web: a dialog that scrolls inside itself shows what was on screen. Revisit if an app needs it. |
| C5 | Only the largest vertical scroll view is captured at full length. Others show what was on screen. | shipped | shipped | shipped | Web: the document scroll is full length. An inner `overflow` container shows what was on screen, with frames clipped to it. |
| C6 | A full-length capture stops at a height limit and ends between two rows. | shipped | no | no | Web: a tall page is drawn whole at a lower scale, so the capture fits a 16 megapixel canvas, the limit of iOS Safari. |
| C7 | Presented layers are separate. A tap on a layer selects only what is inside it, and content a layer hides completely is left out. | shipped | shipped | shipped | iOS: sheets, popovers, alerts, covers, and menus. Web: modal `<dialog>` elements, open popovers, and `aria-modal` dialogs. |
| C8 | The keyboard is drawn as a gray block, and taps there select the keyboard. | shipped | no | no | Web: a desktop has no on-screen keyboard, and a phone's keyboard is not in the DOM. |
| C9 | Accessibility elements are switched on for the capture and restored after. | shipped | no | no | Web: the DOM always carries roles and names. |
| C10 | The capture records the environment. | shipped | shipped | shipped | iOS: app, location, version, device, display, time, and locale. Web: app name and version from `setupFeedbackEngine()`, the URL's path, the browser and platform, the viewport with its pixel ratio and color scheme, time, and locale. |
| C11 | The capture records a screen name. | shipped | shipped | shipped | iOS: the topmost navigation title, or the selected tab's. Web: `document.title`. |
| C12 | The app attaches its own state to every capture. | shipped | shipped | shipped | iOS: `Feedback.context(name) { value }`. Web: `context(name, () => value)`. The function runs when a capture is taken. |
| C13 | Rows that a lazy container has not created are missing. | shipped | shipped | shipped | The same limit holds for virtualized lists on the web. |
| C14 | Scrolling during a capture is real, so code that reacts to it runs. | shipped | shipped | shipped | Web: the window jumps to its origin and back inside one task, so nothing is painted, and scroll listeners run. |
| C15 | A modal's dimmed backdrop, an open popover, and the state of form fields are in the screenshot. | shipped | shipped | shipped | iOS: they are pixels like any other. Web: a re-draw of the DOM loses all three, so the capture paints the backdrop, keeps the copy of an open popover displayed, and writes each field's state into the copy. A placeholder is drawn in the field's text color. |

## Tree

| ID | Feature | iOS | Svelte | React | Notes |
| --- | --- | --- | --- | --- | --- |
| R1 | Nodes are numbered depth-first in reading order, so a parent has a lower number than its children. | shipped | shipped | shipped | Web: `buildTree` in the TypeScript core. |
| R2 | An element's parent is the smallest component that holds its centre and three quarters of its area, or else the smallest that holds its centre. | shipped | shipped | shipped | Web: DOM ancestry gives the parent directly. A React component that renders several elements is one box around them. |
| R3 | Hit-testing picks the smallest node under the point, on the topmost layer that covers it. | shipped | shipped | shipped | |
| R4 | A tagged component inside a button or link is a child of that button or link. | shipped | shipped | shipped | Web: true by DOM ancestry. |
| R5 | The same part in sibling components is found, such as the same button in every row. | shipped | shipped | shipped | |
| R6 | Frames are clipped to the capture. | shipped | shipped | shipped | |
| R7 | A button, a link, or a switch is one element with its content merged into its label, so the text inside it cannot be picked by itself. A tagged component inside it still can. | shipped | shipped | shipped | iOS: the accessibility tree merges them. Web: an untagged descendant of an element with a control's role is not a node. |
| R8 | Only leaf elements become nodes. A container is walked through, even when it has a label. | shipped | shipped | shipped | Web: landmark, list, and group roles are walked through. A text that wraps a control, such as a label around its field, is the control's parent. |

## Editor

| ID | Feature | iOS | Svelte | React | Notes |
| --- | --- | --- | --- | --- | --- |
| E1 | The editor shows the frozen screenshot. A tap selects the most specific node under it. | shipped | shipped | shipped | |
| E2 | The same part in sibling components is outlined faintly. | shipped | shipped | shipped | |
| E3 | The screenshot scrolls to reach content that was off screen, and zooms up to 4×, also while typing. | shipped | shipped | shipped | iOS: pinch. Web: Ctrl with the wheel, which is also what a trackpad pinch sends. A touch-screen pinch is written and not tested, because Playwright cannot pinch. |
| E4 | The selection sits between its parent and its child. Tapping either moves the selection. | shipped | shipped | shipped | |
| E5 | The user types feedback and submits it. Each item gets a numbered box. | shipped | shipped | shipped | Web: Enter submits, and Shift with Enter adds a line. The number badge of a box at the screenshot's edge is drawn whole, outside the picture's rounded corners. |
| E6 | A tap inside a numbered box brings back that item's feedback for editing. A second tap drills down. | shipped | shipped | shipped | |
| E7 | Feedback belongs to one level of the hierarchy. | shipped | shipped | shipped | |
| E8 | A list shows the items, lets the user remove them, and shows the context that will be attached. | shipped | shipped | shipped | |
| E9 | Closing asks first when items were never shared, and gives focus back to the field that had it. | shipped | shipped | shipped | |
| E10 | A draft survives a visit to a target that already has feedback. | shipped | shipped | shipped | |
| E11 | While the editor is open, assistive technology and UI automation see only the editor. | shipped | shipped | shipped | iOS: hides the app's windows from accessibility. Web: a modal dialog in the top layer makes the page inert. |
| E12 | The editor's text stops growing at the largest standard text size. | shipped | no | no | Web: browsers zoom the whole page, so the screenshot scales with the text. |
| E13 | Hovering shows which node a click would select. | no | shipped | shipped | iOS: a touch screen has no hover. |
| E14 | Typing `@` in the feedback text references another element. A tap picks it, arrows move to its parent or child, and **Insert** writes a token such as `@1_Dialog`. | shipped | shipped | shipped | |
| E15 | Items and references share one count: an element keeps one number for the whole capture, whether an item or a reference gave it, so no two boxes show the same number. A referenced element's box gets an `@N` tag. | shipped | shipped | shipped | |
| E16 | The screenshot's scale stays fixed while the panel under it grows. | shipped | shipped | shipped | |
| E17 | The editor's styles and the app's styles do not reach each other. | shipped | shipped | shipped | iOS: a separate window. Web: a shadow root. |
| E18 | Tapping the selection's title shows its component's `file:line`, the number of similar parts, and its data in a popover. The panel itself shows only the title, so the field has the room. | shipped | shipped | shipped | iOS: a popover with its arrow on the title. Web: a tooltip above the title on a narrow screen, and below it beside the screenshot. A click elsewhere or Escape closes it. |
| E19 | The feedback field grows with its text up to 60% of the editor's height, then scrolls. | shipped | shipped | shipped | iOS: the height above the keyboard. Web: the viewport's height. |

## Export and sharing

| ID | Feature | iOS | Svelte | React | Notes |
| --- | --- | --- | --- | --- | --- |
| X1 | The image export is one `feedback.png` with numbered boxes, a card per item, and the environment. Each card has the text at the top and the target with its `file:line` in a band at the bottom. The environment sits at the top of the right column, with that column's cards under it. A tall capture is cut half a screen below the lowest box or card, and is at least one screen tall. | shipped | shipped | shipped | Web: drawn on a canvas with the layout rules of `report.md`. |
| X2 | The JSON export is one `feedback.json` with the items, the tree, the component data, and the context. | shipped | shipped | shipped | |
| X3 | Image and JSON export together as one `feedback.zip`. | shipped | shipped | shipped | |
| X4 | **Copy Feedback** puts the image export on the clipboard as one PNG. | shipped | shipped | shipped | Web: `navigator.clipboard.write`, in a secure context. |
| X5 | **Copy Feedback** puts the JSON export on the clipboard as JSON and plain text. | shipped | shipped | shipped | Web: plain text only, the one text type browsers accept. |
| X6 | **Copy Feedback** for the ZIP puts both the image and the JSON on the clipboard, as two items. | shipped | shipped | shipped | Web: browsers accept one clipboard item per write. The web writes one item with a PNG and a plain-text representation, and the paste target picks one. |
| X7 | The export goes to any system share target, such as Messages, Notes, or Files. | shipped | shipped | shipped | Web: **Save File** downloads it. **Share…** shows where the browser has `navigator.share` for files, and is not tested, because a headless browser has none. |
| X8 | Each export is written to a file an agent can read without the share sheet. | shipped | shipped | shipped | iOS: `tmp/feedback.*` in the app's container. Web: `__feedbackEngine.lastExport` on the page holds the files. |
| X9 | An item counts as shared once a share completes. | shipped | shipped | shipped | |
| X10 | The exports carry the references. The image draws a box for each referenced node and highlights each token in its color. The JSON lists them under `references`. | shipped | shipped | shipped | |

## ProcrastiMate

| ID | Feature | iOS | Svelte | React | Notes |
| --- | --- | --- | --- | --- | --- |
| P1 | The Share menu posts the feedback to ProcrastiMate as one task. | shipped | shipped | shipped | Web: through the dev server. ProcrastiMate's API sends no CORS headers, so `feedbackProcrastimate()` from `@smirea/feedback-engine/vite` forwards the page's calls and adds the token there. A deployed static site has no such server and no ProcrastiMate entry. |
| P2 | The post uses the session ProcrastiMate shares with the team's other apps. | shipped | no | no | iOS: the shared keychain group. Web: browsers share no storage across origins. The dev server holds a token instead, from its own environment. |
| P3 | A picker lists projects with their icons and sections, with the last project already selected. | shipped | shipped | shipped | Web: without the icons, which are SF Symbols on iOS. |
| P4 | The task name starts as the screen's name, `Feedback`, and the item count. | shipped | shipped | shipped | |
| P5 | An on-device language model summarizes the items into the task name without blocking the post. | shipped | planned | planned | iOS: Apple Intelligence. **Add** before the model answers hands its work to the outbox: a post still waiting goes out under the summary, and a task already made is renamed once. A typed name stays. A relaunch asks the model again only for a post whose task does not exist yet, so a late rename never undoes one made in ProcrastiMate. Web: Chrome's built-in model. Not built, because Chrome reports the model as unavailable on the machine this was developed on, so it could not be checked. |
| P6 | The task carries the image export as JPEG with a thumbnail, and `feedback.json`. | shipped | shipped | shipped | |
| P7 | A toast confirms the post and opens the task when tapped. | shipped | shipped | shipped | iOS: `procrastimate://task/<id>`. Web: the task's page in the ProcrastiMate web app. |
| P8 | The Share menu lists ProcrastiMate only where a post can work. Elsewhere the entry is not there. | shipped | shipped | shipped | iOS: the app's entitlements include ProcrastiMate's keychain group, which only an app of the same Apple team can have. Web: `feedbackProcrastimate()` has a token, and tells the page so. The example apps read it from `PROCRASTIMATE_TOKEN`. |
| P9 | **Add** saves the post to an outbox on the device and closes at once. The outbox sends it, and keeps it through no connection, a timeout, and a relaunch until it lands. | shipped | planned | planned | iOS: files under Application Support, sent at launch, on foreground, when the network returns, and on a backoff up to 15 minutes. Every request is idempotent: the server keeps the first bytes stored under an image id, and `POST /api/tasks` with the client's task id returns that task, so a retry resumes where the last attempt stopped and never adds a second task. A task deleted before a retry heard back answers 410, and the post leaves the outbox. A post the server refuses for good waits for **Retry Now** or **Discard** in the sheet. Web: the page posts through the dev server on the same machine, so it waits on the post instead. An IndexedDB outbox retried on `online` would match iOS. |
| P10 | A failure shows above the project list with its message, the step, request, status, response, and capture context under **Details**, and **Copy Error**. | shipped | shipped | shipped | A failure under a long project list once went unseen, so a failed post looked like a spinner that stopped. iOS: the sheet also lists each post still waiting, with its last failure. |

## Agent workflow

| ID | Feature | iOS | Svelte | React | Notes |
| --- | --- | --- | --- | --- | --- |
| A1 | A skill tells an app's agents how to make screens accessible and precise to point at. | shipped | shipped | shipped | `skills/feedback-accessibility` has one section per package: SwiftUI, Svelte, and React. |
| A2 | A script replays every tap on an exported tree and reports the taps that fall through. | shipped | shipped | shipped | `skills/feedback-accessibility/scripts/taps.py` reads `feedback.json`, so it runs on a web export unchanged. |
| A3 | An example app with every screen tagged is there to try Feedback on. | shipped | shipped | shipped | iOS: `examples/todo-ios`. It is not in ProcrastiMate's keychain group, so a post needs another app. Web: `examples/todo-svelte` and `examples/todo-react`, the same app twice. |
| A4 | An agent can trigger a capture and read the export without a person. | shipped | shipped | shipped | iOS: `simctl` shake and the app's container. Web: `__feedbackEngine.present()` and `__feedbackEngine.lastExport` from Playwright. |
