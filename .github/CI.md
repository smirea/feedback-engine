# Continuous integration

`workflows/ci.yml` runs checks, tests, and builds on pull requests, pushes to `master`, and manual dispatches, one job per check, all in parallel. A newer push cancels the run in progress. All CI helpers run with Bun, pinned by `.bun-version`.

The Bun jobs run on every change, one per root script: `lint:ci`, `typecheck`, `test`, and `build`, the same scripts the commit hook calls. Each times out after 5 minutes. `lint:ci` also runs `scripts/check-features.ts` and `scripts/check-package.ts`.

The web and Swift jobs sit behind `changes`, which runs `scripts/changes.ts`. When their inputs did not change, they report success from a Linux runner, so their checks stay green without a browser run or a macOS runner. Documentation changes are ignored, except under `spec/`, which the checks and tests read. Workflow changes and manual dispatches run every job. Edit `scripts/changes.ts` when the layout changes. A failure in change detection fails those jobs too.

Actions are pinned to commit SHAs. Dependabot checks for action updates weekly.

The web job runs `test:web`, the browser suite, which reads pages of `examples/todo-svelte` and `examples/todo-react` on their dev servers in Chromium and WebKit, and three separate apps, Svelte, React, and Next.js, that install the packed package. It never drives the editor, and no git hook runs it. It caches the browsers by lockfile. Their system libraries come from Ubuntu's mirrors on every run. When the runner cannot resolve those mirrors, the step switches to a public resolver, or stops at once if that fails too. Keep CI checks read-only. `.bun-version` and `packageManager` pin Bun. Update them together. Commit `bun.lock` after changing dependencies. CI caches package downloads, then always installs with `--frozen-lockfile`.

CI never installs or runs env-manager. The committed `env.ts` validates the environment, and every variable it requires has a default in the tracked `.env`, which Bun loads for the scripts CI runs from the repository root. A job that needs a real credential takes it from a GitHub Actions secret in its `env:`. Keep the defaults harmless and complete enough for CI. Never commit `.env.local`.

Pull requests also run `changeset`, which fails when the web package changed without a changeset since the base. `.changeset/config.json` counts `packages/web/src`, tests aside, and `packages/web/package.json` as changes. The pre-push hook runs the same check against `origin/master`, and nothing else.

Swift runs as two jobs when `Package.swift`, `packages/ios`, `examples/todo-ios`, or `spec/fixtures` change. `package` runs `swift test`, which compiles the package for macOS and runs its tests. `app` compiles `examples/todo-ios` for a generic iOS simulator without signing, which also compiles the package's UIKit files that `swift test` skips. Neither boots a simulator. Both run on GitHub's `xcode-27` image with its installed Xcode and Swift.

## Releases

`workflows/release.yml` runs after every CI run on a push to `master` and acts only when CI passed. It runs `scripts/release.ts`, which:

1. Stops when `master` has moved past the commit CI tested. The CI run for the newer commit releases it.
2. Runs `changeset version` when changesets are pending, which bumps `packages/web/package.json`, writes `packages/web/CHANGELOG.md`, and deletes the changesets. `bun install` then updates the workspace's version in `bun.lock`.
3. Publishes the package with `npm publish` unless npm already has that version.
4. Commits the version as `github-actions[bot]` and pushes it to `master`. A push made with the workflow's token starts no CI run, so a release never triggers another.

Publishing comes before the push so a rerun converges: npm skips a version it has, and the commit is pushed then. npm trusts this workflow by its file name through [trusted publishing](https://docs.npmjs.com/trusted-publishers), so no token is stored anywhere, and every version carries provenance. Renaming `release.yml` breaks publishing until the trusted publisher on npmjs.com names the new file. The package's npm settings disallow publishing with tokens.
