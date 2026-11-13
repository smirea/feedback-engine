# Feedback export format

Every platform package exports a capture in one of two formats, each a single file, so agents read feedback from any app the same way. The iOS package is the reference implementation (`packages/ios/Sources/Feedback/Report.swift` and `AnnotatedImage.swift`). The web package's core is in `packages/web/src/core`. `spec/fixtures/capture.json` holds one tree with the answers both must give for it, and both test suites read it.

## Capture model

A capture is a screenshot plus a tree of nodes. Node 0 is the whole capture. When the screen's main scroll view has more content than fits, the capture shows that content at full length: the bars above it stay at the top, the bars below it move to the bottom, and the capture is taller than the device screen. The same holds for the main scroll view of a sheet expanded to full height: the sheet's layer grows with the capture, and the screen behind it stays put. A capture that reaches its height limit ends between two rows. On the web the whole document is the capture, drawn at a lower scale when it is very tall, and content that stays put while the page scrolls, such as a fixed tab bar, is where it was on screen. The capture records which part was on screen when it was taken. Nodes are numbered depth-first in reading order, so a parent always has a lower number than its children.

| Field | Meaning |
| --- | --- |
| `kind` | `screen`, `layer` (a presented sheet, popover, dialog, or menu, or the keyboard), `component` (tagged by the app), or `element` (from the accessibility tree) |
| `name` | Component name, layer name, or element role (`Button`, `Switch`, `Text`, `Text field`, `Header`, `Image`, …) |
| `label` | Visible text of an element |
| `frame` | Rectangle in points from the capture's top-left corner, clipped to the capture |
| `source` | `file:line` of the component's tag call. On the web, an element has one too in development builds, where the framework records it. |
| `data` | Text description of the component's data at capture time |
| `layer` | 0 for the base screen. Higher layers are presented on top. |

Hit-testing picks the smallest node under the point, considering only the topmost layer that covers it. A node that a higher layer covers completely can never be picked, so the tree leaves it out. Content hidden under the bars or a pinned section header or footer of a full-length capture is left out too. Each section header and footer appears once, in its own place, except the header of a section that starts above the capture, which stays where it was pinned on screen.

Where the platform knows the real hierarchy, as the web does from the DOM, a node's parent is the nearest node above it. Where it does not, as on iOS, an element's parent is the smallest component that holds its centre and at least three quarters of its area, or else the smallest that holds its centre. Of two components with the same frame, the inner one wins.

## Component data

A component's `name` is its type name without generic arguments, such as `DashboardCard`. Its `data` is one `label: value` line per property, or the description of the value the app passed. Values are written as follows:

- Strings are plain at the top level and quoted inside other values. A missing value is `nil`.
- Floating-point numbers keep 3 decimals, or 3 significant digits below 1, without trailing zeros: `72.575`, `0.123`, `60`. Values that would need more than 15 decimals use exponent notation, such as `1.23e-16`.
- Structured values are `Type(field: value, …)`, enum cases with values are `case(value)`, lists are `[a, b]`, and maps are `[key: value]`. A value with its own text description uses it.
- Nesting stops after 3 levels as `Type(…)`, `case(…)`, `[…]`, or `(…)`, and lists after 10 elements as `… N more`. The whole description stops at 1,500 characters, followed by `… (truncated)`.
- Values in `context` use the same format with 6 levels of nesting and up to 8,000 characters.
- Closures, framework internals such as environment values, and values made only of those are left out.

The web writes JavaScript values with the same rules and these spellings:

- A missing value is `null` or `undefined`, as the value is.
- A plain object is `{field: value}` and a class instance is `Type(field: value)`. A class's getters count as fields. Past the nesting limit they are `{…}` and `Type(…)`.
- A plain object passed as a component's data is one `label: value` line per property.
- A `Map` is `[key: value]`, and an array or a `Set` is `[a, b]`.
- A `Date` is its ISO 8601 string. A value with a `toFeedback()` method is described as what that method returns.
- Functions, DOM nodes, and values made only of those are left out.

## References

Item text can name other nodes with reference tokens such as `@1_Dialog`: `@`, the node's number, `_`, and the node's `name` with each run of characters other than letters and digits replaced by one `_`. A token followed directly by more letters or digits is plain text.

Items and references share one count. A node takes the next number, from 1, and the next color of one palette the first time it is given an item or a reference, and keeps both for the whole capture. An item's number and a reference's number are its node's number, so a node with both shows one number and one color, and no two nodes show the same number. A node referenced again keeps its first token. Removing an item leaves its number unused, so numbers can have gaps.

## Image export

The screenshot sits between two columns. Each item's target has a dashed box with no fill and a round badge with its number, matching the item numbers in the JSON export. Each node an item's text references has a box in its color too, with its `@N` in a square tag on the box's top-right corner. In the cards, each reference token is drawn in white on its color, with a space of that color before and after it. Each item goes in a card in the left column, with its text at the top beside the badge, and its target title over the nearest component's `file:line` at the bottom, in dark text of one small size on a band filled with the card's border color, as level with the target as the cards above it allow, with a line from the card to the nearest side of the box. A card moves to the right column only when that makes its line at least 80 points shorter, as for a target at the right edge. The app name and the environment entries always go at the top of the right column, and the cards in the right column go below them. The screenshot is cut half the height of the part that was on screen below the lowest item box, reference box, or card, but never shorter than that height and never past the capture's end. A tall capture is drawn at a lower scale, so the image stays under about 40 million pixels.

## JSON export

The JSON export carries everything the capture knows except the image, as one object with sorted keys. Numbers are points, rounded to one decimal.

| Key | Contents |
| --- | --- |
| `app` | App name |
| `captured` | ISO 8601 date of the capture |
| `size` | `width` and `height` of the whole capture |
| `visible` | `x`, `y`, `width`, `height` of the part that was on screen |
| `environment`, `context` | Arrays of `name` and `value`, in the order the app registered them |
| `items` | In the order they were added: `number` (the target's number, see References), `text`, `target` (node id), `title`, `path` (node ids from the screen down to the target), and `code`, the `file:line` of the nearest node with a `source`, from the target up, when there is one |
| `references` | Each reference some item's text uses, by number: `number`, `token`, and the same `target`, `title`, `path`, and `code` as an item |
| `nodes` | Every node in id order: `id`, `parent`, `layer`, `kind`, `name`, `label`, `frame`, `source`, and `data`. Keys without a value are left out. |

## Sharing

The Share menu offers three exports and a ProcrastiMate post.

- **Image** shares one `feedback.png`. The copy action writes one PNG pasteboard item.
- **JSON** shares one `feedback.json`. The copy action writes one pasteboard item with JSON and plain-text representations of the same document.
- **Image and JSON** shares one `feedback.zip` holding both files in a `feedback` folder. The copy action writes both pasteboard items. A browser takes one clipboard item per write, so the web writes one item with the PNG and the JSON as plain text.
- **ProcrastiMate** creates one task in the picked project, or the Inbox. The picker shows each project with its ProcrastiMate icon. A picked project with sections lists them under it, with `No section`, the project's top, first and picked. Its title is an editable name that starts as the screen's name, ` Feedback: `, and the item count, such as `Groceries Feedback: 3 changes` (`1 change` for one). Where an on-device language model is available, it summarizes every item in a few words without blocking the post, and an untouched name becomes the count, the screen's name, ` Feedback: `, and the summary, such as `3 Groceries Feedback: bigger titles, remove the share button`. The screen's name is the topmost navigation title, or the selected tab's title when no bar has one, or the app's name. Its notes stay empty. It has two attachments: the image export as JPEG, at most 2,048 pixels wide and 1.5 MB, with a thumbnail at most 320 pixels wide and 200 KB, and the JSON export, minified, as the file `feedback.json`, uploaded in ProcrastiMate's 1.5 MB parts. Both are uploaded before the task is created. The confirmation toast opens the task in ProcrastiMate (`procrastimate://task/<id>`) when tapped. On the web the picker has no icons, the name is not summarized, and the toast opens the task's page in the ProcrastiMate web app (`/inbox?task=<id>`).
