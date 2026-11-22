# @stefan.inc/feedback-engine

## 1.7.0

### Minor Changes

- 82d0a0b: The package now ships the `feedback-accessibility` skill, and `bunx feedback-engine init` links it into your app's `.agents/skills` and adds a Feedback section to `AGENTS.md`, so your agents find the skill and the editor. `__feedbackEngine.capture()` returns a screen's JSON export without opening the editor, for agents that check what each tap selects. The skill's tap replay is now `scripts/taps.js`, run with `node` or `bun`, in place of the Python script.

### Patch Changes

- 4dbf098: The screenshot stays sharp on high-density screens. The page is copied once as vector images, so the editor redraws the part in view at the screen's resolution at any zoom, and the image export renders at the screen's pixel ratio instead of a scale lowered to fit one canvas. A capture now follows the iOS rules for long pages: it stops at 16,000 device pixels (8,000 CSS pixels on a 2x screen), ends between two rows, and centers on the part on screen when the page was scrolled deep. Pages with images capture much faster in Safari, which used to wait about a tenth of a second per image.

## 1.6.3

### Patch Changes

- 63c7af9: Items and references cycle through 12 distinct colors instead of 8, so the first 12 marked elements never share a color, and no two look alike (red and pink did before).

## 1.6.2

### Patch Changes

- ebb4696: **Copy Error** sits directly under a failure's message, above **Details**, so it stays in view when the details are long.
- 01f1e91: An export that cannot be copied, saved, or shared shows a red toast that stays until it is clicked, and the click opens the whole error with **Copy Error**. The toast used to be green with a check mark and left after three seconds.

## 1.6.1

### Patch Changes

- bb82595: Posting to ProcrastiMate uploads the JSON report as one file, with its name and type, which is how ProcrastiMate now stores files. ProcrastiMate no longer takes the parts earlier versions sent, so an app on an earlier version cannot post a report there.

## 1.6.0

### Minor Changes

- d06d20c: The editor lists every feedback item under the text field. Clicking one edits it, and while you type an `@` reference it picks that item's element. The list starts closed on narrow screens.

## 1.5.0

### Minor Changes

- c95fc4a: `feedbackProcrastimate({ project })` names the ProcrastiMate project the picker opens on, by name or id, in place of the last project posted to. `setupFeedbackEngine({ procrastimate: { project } })` does the same for a proxy of your own.

## 1.4.0

### Minor Changes

- c72f332: The Share menu ends with **New Webhook**, which adds a webhook from the editor: a name, a URL, an optional header, and whether to attach the JSON export and the image export, as PNG or JPEG with a compression. The browser keeps it for the site, and choosing it opens it to send, change, or delete it. Its post carries `title`, `image`, `feedback`, and `device`. Webhooks the app lists keep their request.

## 1.3.0

### Minor Changes

- 45f2c3e: `setupFeedbackEngine({ pinned })` chooses which Share menu entries get a button beside Share, by name, such as `['ProcrastiMate']`. The others stay in the Share menu. Without it, the first two still get one.

### Patch Changes

- 45f2c3e: The editor's header drops the Feedback list button and its sheet. Share now sits left of the pinned buttons, and the header's buttons are plain icons, larger than before, with no round background.

## 1.2.4

### Patch Changes

- 1d55df5: The image export keeps the same margin on every edge and centers the GitHub watermark in the top margin, so the app's details and the screenshot start at the top of the content again.

## 1.2.3

### Patch Changes

- 3d017a5: The image export moves the GitHub watermark to the top corner above the app's details, with a smaller mark. Connectors now match the dashed box's stroke width and have a dot where they leave the card.

## 1.2.2

### Patch Changes

- c385730: The image export puts references that have no card under a small References header, and adds a faint GitHub watermark with the repository's URL at the bottom of the card column.

## 1.2.1

### Patch Changes

- 2fe6e6d: The image export joins each card to its box with an S curve and places cards so their curves avoid other boxes and each other. When one column of cards fits without a crossing, the image drops the other column and is narrower. The environment reads as `Name: value` lines, and each reference without a card of its own gets a `@N file:line title` line under it.

## 1.2.0

### Minor Changes

- 9c151d3: On a phone, holding three fingers still on the screen opens Feedback. A capsule grows at the top center while the fingers are down, and the page is captured after 0.7 seconds. Pass `threeFingerHold: false` to turn it off. Long component names in the editor now wrap instead of pushing the panel past a phone's screen.

## 1.1.0

### Minor Changes

- 05fb2e4: ProcrastiMate and the app's webhooks get buttons with their icons beside Share, up to two, so a post takes one tap. The Share menu lists ProcrastiMate first, with its app icon, then webhooks with `githubIcon`, then the others.

## 1.0.2

### Patch Changes

- a074680: A new feedback item now takes its number before the elements it references. Feedback on a header that references two rows is numbered 1, and the rows are 2 and 3, where before the rows took 1 and 2 and the item took 3. References added while editing an existing item still take the next number.

## 1.0.1

### Patch Changes

- d302c9d: The package's npm page has the full web guide, for Svelte, React, and Next.js, with an editor screenshot and an exported image.

## 1.0.0

### Major Changes

- f3e7373: The first release on npm, as `@stefan.inc/feedback-engine`. It replaces the GitHub install, `github:smirea/feedback-engine`, and `@smirea/feedback-engine` imports become `@stefan.inc/feedback-engine`.
