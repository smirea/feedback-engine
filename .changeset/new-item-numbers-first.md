---
'@stefan.inc/feedback-engine': patch
---

A new feedback item now takes its number before the elements it references. Feedback on a header that references two rows is numbered 1, and the rows are 2 and 3, where before the rows took 1 and 2 and the item took 3. References added while editing an existing item still take the next number.
