---
'@stefan.inc/feedback-engine': minor
---

- ProcrastiMate can now post through a popup on the ProcrastiMate web app (`/feedback`) using whoever is signed in there, with no hardcoded token, no proxy, and no CORS: pass `setupFeedbackEngine({ procrastimate: { projects: ['Your Project'] } })` without `url`.
- ProcrastiMate posts only to the projects an app lists, and nothing allows every project. `feedbackProcrastimate()` and `setupFeedbackEngine({ procrastimate })` require a non-empty `projects` list (by name or id), the picker no longer offers the Inbox, and both the dev server's proxy and ProcrastiMate's `/feedback` popup enforce the list.
