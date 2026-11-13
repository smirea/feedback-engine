# @stefan.inc/feedback-engine

**Point at your app. Say what's wrong. Hand an agent the exact component and line of code.**

Alt+Meta+click anything in your Svelte or React app, click any component on the frozen screenshot, and write what should change. Feedback exports one file that names every component you flagged, where it lives in the source, and the data it was showing, so an agent can act on the feedback without guessing.

```sh
bun add @stefan.inc/feedback-engine
```

The package has one entry point per framework, `/svelte` and `/react`, with build plugins in `/vite` and `/next`. It ships TypeScript and Svelte source, and your app's bundler compiles it.

Setup for Svelte, React, and Next.js, and everything else the package does, is in the [repository's README](https://github.com/smirea/feedback-engine#web). [CHANGELOG.md](https://github.com/smirea/feedback-engine/blob/master/packages/web/CHANGELOG.md) lists every release.
