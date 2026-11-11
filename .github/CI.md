# Continuous integration

`workflows/ci.yml` runs checks, tests, and builds on pull requests, pushes to `master`, and manual dispatches. Each task reports success when its stack has no relevant changes. Manual dispatches run every task. Documentation changes are ignored, except under `spec/`, which `bun test` checks. Workflow changes run every task. Edit `scripts/changes.ts` when the layout changes. All CI helpers run with Bun, pinned by `.bun-version`.

Actions are pinned to commit SHAs. Dependabot checks for action updates weekly. A failure in change detection fails the task jobs too.

Bun tasks run the root `lint:ci` and `typecheck`, `test`, and `build` scripts. The web task runs `test:web`, which drives `examples/todo-svelte` and `examples/todo-react` with Playwright in Chromium and WebKit, and two separate apps, one Svelte and one React, that install the packed package. It caches the browsers by lockfile. Keep CI checks read-only. `.bun-version` and `packageManager` pin Bun. Update them together. Commit `bun.lock` after changing dependencies. CI caches package downloads, then always installs with `--frozen-lockfile`.

CI regenerates the ignored `.env.local` from the tracked `.env` defaults with the pinned env-manager. Keep the defaults harmless and complete enough for CI. Never commit `.env.local`.

Swift tasks run when `Package.swift`, `packages/ios`, `examples/todo-ios`, or `spec/fixtures` change. Both platforms' tests read `spec/fixtures`, so a change there runs the Bun tasks too. Checks compile the package for macOS with `swift build`. Tests run `swift test`. Builds compile `examples/todo-ios` for a generic iOS simulator without signing, which also compiles the package's UIKit files that `swift build` skips. Swift jobs run on GitHub's `xcode-27` image with its installed Xcode and Swift.
