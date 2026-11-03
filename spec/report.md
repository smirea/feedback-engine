# Feedback export format

Every platform package exports a capture in one of two formats, each a single file, so agents read feedback from any app the same way. The iOS package is the reference implementation (`packages/ios/Sources/Feetback/Report.swift` and `AnnotatedImage.swift`).

## Capture model

A capture is a screenshot plus a tree of nodes. Node 0 is the whole capture. When the screen's main scroll view has more content than fits, the capture shows that content at full length: the bars above it stay at the top, the bars below it move to the bottom, and the capture is taller than the device screen. The capture records which part was on screen when it was taken. Nodes are numbered depth-first in reading order, so a parent always has a lower number than its children.

| Field | Meaning |
| --- | --- |
| `kind` | `screen`, `layer` (a presented sheet, popover, or dialog), `component` (tagged by the app), or `element` (from the accessibility tree) |
| `name` | Component name, layer name, or element role (`Button`, `Text`, `Header`, `Image`, …) |
| `label` | Visible text of an element |
| `frame` | Rectangle in points from the capture's top-left corner |
| `source` | `file:line` of the component's tag call |
| `data` | Text description of the component's data at capture time |
| `layer` | 0 for the base screen. Higher layers are presented on top. |

Hit-testing picks the smallest node under the point, considering only the topmost layer that covers it.

## Image export

The screenshot sits between two columns. Each item's target has a dashed box with no fill and a numbered badge, matching the item numbers in the JSON export. Each item's target title, the nearest component's `file:line`, and the text go in a card in the left column, as level with the target as the cards above it allow, with a line from the card to the box. A card moves to the right column only when that puts it at least 80 points closer to its target. The right column starts with the app name and the environment entries. A tall capture is drawn at a lower scale, so the image stays under about 40 million pixels.

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

The editor offers two export formats, and the choice persists between captures.

- **Image** shares one `feedback.png`. The copy action writes one PNG pasteboard item.
- **JSON** shares one `feedback.json`. The copy action writes one pasteboard item with JSON and plain-text representations of the same document.
