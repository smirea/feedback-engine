---
'@stefan.inc/feedback-engine': patch
---

`feedback-engine init` works from a monorepo's root. It finds the package in the workspace that installed it, as Bun's isolated installs leave it, and writes the section for that workspace's framework, so the skill and the Feedback section sit at the repository's root, where every agent reads them.
