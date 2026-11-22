---
'@stefan.inc/feedback-engine': major
---

- ProcrastiMate can now post through a popup on the ProcrastiMate web app (`/feedback`) using whoever is signed in there, with no hardcoded token, no proxy, and no CORS: pass `setupFeedbackEngine({ procrastimate: { projects: ['Your Project'] } })` without `url`.
- ProcrastiMate posts only to the projects an app lists, and nothing allows every project. `feedbackProcrastimate()` now requires `projects`, by name or id, and throws without it, as does `setupFeedbackEngine({ procrastimate })` without `procrastimate.projects`. Add `projects: ['Your Project']` to upgrade. The picker no longer offers the Inbox, and both the dev server's proxy and ProcrastiMate's `/feedback` popup enforce the list.
