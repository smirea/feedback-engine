# Feedback report format

Every platform package produces the same two artifacts from one capture, so agents read feedback from any app the same way. The iOS package is the reference implementation (`packages/ios/Sources/Feetback/Report.swift` and `AnnotatedImage.swift`).

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

## Markdown report

Sections appear in this order:

1. `# Feedback: <app>`, a short preamble about the image and coordinates (for a full-length capture, it also gives the y range that was on screen), and a bullet list of environment entries: App, Location (tab and navigation titles), Version, Device, Display, Captured (ISO 8601), Locale.
2. One `## <n>. <target title>` section per item, numbered from 1. The feedback text is a blockquote. Bullets follow: `Path` (screen to target, with `file:line` for components), `Frame`, `Element` for accessibility targets, and `Code`, the nearest tagged component.
3. `## Component data`: the data of every component on any item's path, each listed once. Each heading names the component, its `file:line`, and the item numbers whose path includes it.
4. `## App context`: app-registered state, one fenced block per entry.
5. `## Screen outline`: the whole node tree, indented, with frames and source locations.

## Annotated image

The screenshot sits between two columns. Each item's target has a dashed box with no fill and a numbered badge, using the same numbers as the report. Each item's target title and text go in a card in the left column, as level with the target as the cards above it allow, with a line from the card to the box. A card moves to the right column only when that puts it at least 80 points closer to its target. The right column starts with the app name and the environment entries. The image still reads on its own when the text gets separated from it. A tall capture is drawn at a lower scale, so the image stays under about 40 million pixels.

## Sharing

One share action delivers both artifacts. The copy action writes two pasteboard items, the PNG first and the markdown second.
