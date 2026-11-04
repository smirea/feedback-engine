# Feedback export format

Every platform package exports a capture in one of two formats, each a single file, so agents read feedback from any app the same way. The iOS package is the reference implementation (`packages/ios/Sources/Feetback/Report.swift` and `AnnotatedImage.swift`).

## Capture model

A capture is a screenshot plus a tree of nodes. Node 0 is the whole capture. When the screen's main scroll view has more content than fits, the capture shows that content at full length: the bars above it stay at the top, the bars below it move to the bottom, and the capture is taller than the device screen. A capture that reaches its height limit ends between two rows. The capture records which part was on screen when it was taken. Nodes are numbered depth-first in reading order, so a parent always has a lower number than its children.

| Field | Meaning |
| --- | --- |
| `kind` | `screen`, `layer` (a presented sheet, popover, dialog, or menu, or the keyboard), `component` (tagged by the app), or `element` (from the accessibility tree) |
| `name` | Component name, layer name, or element role (`Button`, `Switch`, `Text`, `Text field`, `Header`, `Image`, …) |
| `label` | Visible text of an element |
| `frame` | Rectangle in points from the capture's top-left corner, clipped to the capture |
| `source` | `file:line` of the component's tag call |
| `data` | Text description of the component's data at capture time |
| `layer` | 0 for the base screen. Higher layers are presented on top. |

Hit-testing picks the smallest node under the point, considering only the topmost layer that covers it. A node that a higher layer covers completely can never be picked, so the tree leaves it out. Content hidden under the bars or a pinned section header or footer of a full-length capture is left out too. Each section header and footer appears once, in its own place, except the header of a section that starts above the capture, which stays where it was pinned on screen.

An element's parent is the smallest component that holds its centre and at least three quarters of its area, or else the smallest that holds its centre. Of two components with the same frame, the inner one wins.

## Component data

A component's `name` is its type name without generic arguments, such as `DashboardCard`. Its `data` is one `label: value` line per property, or the description of the value the app passed. Values are written as follows:

- Strings are plain at the top level and quoted inside other values. A missing value is `nil`.
- Floating-point numbers keep 3 decimals, or 3 significant digits below 1, without trailing zeros: `72.575`, `0.123`, `60`. Values that would need more than 15 decimals use exponent notation, such as `1.23e-16`.
- Structured values are `Type(field: value, …)`, enum cases with values are `case(value)`, lists are `[a, b]`, and maps are `[key: value]`. A value with its own text description uses it.
- Nesting stops after 3 levels as `Type(…)`, `case(…)`, `[…]`, or `(…)`, and lists after 10 elements as `… N more`. The whole description stops at 1,500 characters, followed by `… (truncated)`.
- Values in `context` use the same format with 6 levels of nesting and up to 8,000 characters.
- Closures, framework internals such as environment values, and values made only of those are left out.

## Image export

The screenshot sits between two columns. Each item's target has a dashed box with no fill and a numbered badge, matching the item numbers in the JSON export. Each item's target title, the nearest component's `file:line`, and the text go in a card in the left column, as level with the target as the cards above it allow, with a line from the card to the nearest side of the box. A card moves to the right column only when that makes its line at least 80 points shorter, as for a target at the right edge. The app name and the environment entries go in the right column, in the first gap from the top that is tall enough for them. A tall capture is drawn at a lower scale, so the image stays under about 40 million pixels.

## JSON export

The JSON export carries everything the capture knows except the image, as one object with sorted keys. Numbers are points, rounded to one decimal.

| Key | Contents |
| --- | --- |
| `app` | App name |
| `captured` | ISO 8601 date of the capture |
| `size` | `width` and `height` of the whole capture |
| `visible` | `x`, `y`, `width`, `height` of the part that was on screen |
| `environment`, `context` | Arrays of `name` and `value`, in the order the app registered them |
| `items` | `number`, `text`, `target` (node id), `title`, `path` (node ids from the screen down to the target), and `code`, the nearest component's `file:line` when there is one |
| `nodes` | Every node in id order: `id`, `parent`, `layer`, `kind`, `name`, `label`, `frame`, `source`, and `data`. Keys without a value are left out. |

## Sharing

The Share menu offers three exports and a ProcrastiMate post.

- **Image** shares one `feedback.png`. The copy action writes one PNG pasteboard item.
- **JSON** shares one `feedback.json`. The copy action writes one pasteboard item with JSON and plain-text representations of the same document.
- **Image and JSON** shares one `feedback.zip` holding both files in a `feedback` folder. The copy action writes both pasteboard items.
- **ProcrastiMate** creates one task in the picked project, or the Inbox. The picker shows each project with its ProcrastiMate icon. A picked project with sections lists them under it, with `No section`, the project's top, first and picked. Its title is an editable name that starts as the screen's name followed by ` Feedback`, such as `Groceries Feedback`. The screen's name is the topmost navigation title, or the selected tab's title when no bar has one, or the app's name. Its notes stay empty. It has two attachments: the image export as JPEG, at most 2,048 pixels wide and 1.5 MB, with a thumbnail at most 320 pixels wide and 200 KB, and the JSON export, minified, as the file `feedback.json`, uploaded in ProcrastiMate's 1.5 MB parts. Both are uploaded before the task is created. The confirmation toast opens the task in ProcrastiMate (`procrastimate://task/<id>`) when tapped.
