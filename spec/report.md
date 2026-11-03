# Feedback report format

Every platform package produces the same two artifacts from one capture, so agents read feedback from any app the same way. The iOS package is the reference implementation (`packages/ios/Sources/Feetback/Report.swift` and `AnnotatedImage.swift`).

## Capture model

A capture is a screenshot plus a tree of nodes. Node 0 is the whole screen. Nodes are numbered depth-first in reading order, so a parent always has a lower number than its children.

| Field | Meaning |
| --- | --- |
| `kind` | `screen`, `layer` (a presented sheet, popover, or dialog), `component` (tagged by the app), or `element` (from the accessibility tree) |
| `name` | Component name, layer name, or element role (`Button`, `Text`, `Header`, `Image`, …) |
| `label` | Visible text of an element |
| `frame` | Rectangle in points from the screen's top-left corner |
| `source` | `file:line` of the component's tag call |
| `data` | Text description of the component's data at capture time |
| `layer` | 0 for the base screen. Higher layers are presented on top. |

Hit-testing picks the smallest node under the point, considering only the topmost layer that covers it.

## Markdown report

Sections appear in this order:

1. `# Feedback: <app>`, a short preamble about the image and coordinates, and a bullet list of environment entries: App, Location (tab and navigation titles), Version, Device, Display, Captured (ISO 8601), Locale.
2. One `## <n>. <target title>` section per item, numbered from 1. The feedback text is a blockquote. Bullets follow: `Path` (screen to target, with `file:line` for components), `Frame`, `Element` for accessibility targets, and `Code`, the nearest tagged component.
3. `## Component data`: the data of every component on any item's path, each listed once. Each heading names the component, its `file:line`, and the item numbers whose path includes it.
4. `## App context`: app-registered state, one fenced block per entry.
5. `## Screen outline`: the whole node tree, indented, with frames and source locations.

## Annotated image

The screenshot at device scale, with a box and a numbered badge around each item's target, using the same numbers as the report. A legend under the screenshot repeats each target title and its text, so the image still reads on its own.

## Sharing

One share action delivers both artifacts. The copy action writes two pasteboard items, the PNG first and the markdown second.
