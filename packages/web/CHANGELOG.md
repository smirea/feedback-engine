# @stefan.inc/feedback-engine

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
