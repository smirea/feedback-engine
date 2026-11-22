---
'@stefan.inc/feedback-engine': minor
---

The package now ships the `feedback-accessibility` skill, and `bunx feedback-engine init` links it into your app's `.agents/skills` and adds a Feedback section to `AGENTS.md`, so your agents find the skill and the editor. `__feedbackEngine.capture()` returns a screen's JSON export without opening the editor, for agents that check what each tap selects. The skill's tap replay is now `scripts/taps.js`, run with `node` or `bun`, in place of the Python script.
