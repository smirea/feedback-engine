# Continuous integration

`workflows/ci.yml` runs checks, tests, and builds on pull requests, pushes to `master`, and manual dispatches. Each task reports success when its stack has no relevant changes. Manual dispatches run every task. Documentation changes are ignored, except under `spec/`, which `bun test` checks. Workflow changes run every task. Edit `scripts/changes.ts` when the layout changes. All CI helpers run with Bun, pinned by `.bun-version`.

Actions are pinned to commit SHAs. Dependabot checks for action updates weekly. A failure in change detection fails the task jobs too.

Bun tasks run the root `lint:ci` and `typecheck`, `test`, and `build` scripts. The web task runs `test:web`, which drives `examples/todo-svelte` and `examples/todo-react` with Playwright in Chromium and WebKit, and two separate apps, one Svelte and one React, that install the packed package. It caches the browsers by lockfile. Their system libraries come from Ubuntu's mirrors on every run. When the runner cannot resolve those mirrors, the step switches to a public resolver, or stops at once if that fails too. Keep CI checks read-only. `.bun-version` and `packageManager` pin Bun. Update them together. Commit `bun.lock` after changing dependencies. CI caches package downloads, then always installs with `--frozen-lockfile`.

CI regenerates the ignored `.env.local` from the tracked `.env` defaults with the pinned env-manager. Keep the defaults harmless and complete enough for CI. Never commit `.env.local`.

Pull requests also run `changeset`, which fails when the web package changed without a changeset since the base. `.changeset/config.json` counts `packages/web/src`, tests aside, and `packages/web/package.json` as changes. The pre-push hook runs the same check against `origin/master`.

Swift tasks run when `Package.swift`, `packages/ios`, `examples/todo-ios`, or `spec/fixtures` change. Both platforms' tests read `spec/fixtures`, so a change there runs the Bun tasks too. Checks compile the package for macOS with `swift build`. Tests run `swift test`. Builds compile `examples/todo-ios` for a generic iOS simulator without signing, which also compiles the package's UIKit files that `swift build` skips. Swift jobs run on GitHub's `xcode-27` image with its installed Xcode and Swift.

## Releases

`workflows/release.yml` runs after every CI run on a push to `master` and acts only when CI passed. It runs `scripts/release.ts`, which:

1. Stops when `master` has moved past the commit CI tested. The CI run for the newer commit releases it.
2. Runs `changeset version` when changesets are pending, which bumps `packages/web/package.json`, writes `packages/web/CHANGELOG.md`, and deletes the changesets. `bun install` then updates the workspace's version in `bun.lock`.
3. Publishes the package with `npm publish` unless npm already has that version.
4. Commits the version as `github-actions[bot]` and pushes it to `master`. A push made with the workflow's token starts no CI run, so a release never triggers another.

Publishing comes before the push so a rerun converges: npm skips a version it has, and the commit is pushed then. npm trusts this workflow by its file name through [trusted publishing](https://docs.npmjs.com/trusted-publishers), so no token is stored anywhere, and every version carries provenance. Renaming `release.yml` breaks publishing until the trusted publisher on npmjs.com names the new file. The package's npm settings disallow publishing with tokens.
