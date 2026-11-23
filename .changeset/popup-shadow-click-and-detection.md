---
'@stefan.inc/feedback-engine': patch
---

Open the ProcrastiMate popup and toast links from the shadow host's light-DOM click bubble so popup blockers that inspect `window.event.currentTarget` recognize the user click, detect fake stub windows returned by popup blockers instead of failing silently, focus reused popup windows, and avoid clamping popup coordinates to `0` on negative-offset monitors.
