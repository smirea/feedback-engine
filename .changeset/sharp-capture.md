---
'@stefan.inc/feedback-engine': patch
---

The screenshot stays sharp on high-density screens. The page is copied once as vector images, so the editor redraws the part in view at the screen's resolution at any zoom, and the image export renders at the screen's pixel ratio instead of a scale lowered to fit one canvas. A capture now follows the iOS rules for long pages: it stops at 16,000 device pixels (8,000 CSS pixels on a 2x screen), ends between two rows, and centers on the part on screen when the page was scrolled deep. Pages with images capture much faster in Safari, which used to wait about a tenth of a second per image.
