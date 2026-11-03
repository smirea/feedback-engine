# TodoDemo

A mock todo app for trying Feetback: lists, a list detail screen, an edit sheet, and settings. Every screen is tagged with `.feedback(self)`. Shake the simulator (**Device › Shake**) on any screen to open the editor. Requires iOS 18, Bun, and Xcode.

## Run

From this folder:

```sh
./scripts/run
```

The launcher selects a target and watches for changes. Edit `Sources/App` to rebuild and relaunch. Stop with Ctrl-C; use `--no-watch` for a single launch. Build errors leave the watcher running.

## Choose a target

```sh
./scripts/run --targets
./scripts/run -t simulator
./scripts/run -t "iPhone 17"
```

`--targets` lists names and identifiers; `*` marks the default. Selection prefers a connected iOS device, then a booted simulator, an available simulator, or My Mac.

Set `SWIFT_RUN_DEFAULT_TARGET` to choose a default; `-t` overrides it. For duplicate simulator names, use an identifier to select exactly. Install simulator runtimes in Xcode's settings.

In an agent worktree, `./scripts/run -t "$(agent-simulator udid)" --headless` runs on the worktree's own simulator. The launcher claims a simulator it targets and waits for room on the Mac before a headless boot (`agent-simulator wait`, exit code 3 means rerun); both steps are skipped without `~/bin/agent-simulator`.

## Device signing

Pair the device in Xcode, enable Developer Mode, and unlock it. Configure automatic signing in Xcode or pass your team:

```sh
./scripts/run --team YOUR_TEAM_ID
```

You can also set `SWIFT_RUN_DEVELOPMENT_TEAM`.

## Debug and build

Open `App.xcodeproj` and select the shared `App` scheme to debug.

Build logs are in `DerivedData/<target>/build.log`, where `<target>` is `device`, `simulator`, or `mac`. Temporary app state resets after relaunch.

The launcher keeps one `DerivedData/SourcePackages` directory per checkout for Swift package downloads, shared by device, simulator, and Mac builds. Compiled outputs stay in their target-specific directories.
