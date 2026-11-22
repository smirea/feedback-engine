---
'@stefan.inc/feedback-engine': minor
---

Remove ProcrastiMate proxy mode (`feedbackProcrastimate()`, `ProcrastimateSheet`, and `url`/`token` on `ProcrastimateConfig`). ProcrastiMate now posts exclusively through the `/feedback` popup on the ProcrastiMate web app using whoever is signed in there: pass `setupFeedbackEngine({ procrastimate: { projects: ['Your Project'] } })`.
