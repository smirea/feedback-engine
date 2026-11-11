# Todo (Svelte)

The web twin of `examples/todo-ios`, for trying Feedback in a browser: lists, a list detail screen with an edit dialog and a popover menu, settings, a long timeline with sticky headers, a catalog with a carousel, and a media screen with charts and images. Every screen is tagged. It is a SvelteKit single-page app.

## Run

From the repository root:

```sh
bun install
bun run dev
```

The dev server listens on `UI_PORT` from the root `.env`, 6180 in the main checkout, and answers at http://feedback-engine.localhost when localias maps that host. An agent worktree gets its own port in `.env.local`.

Press Alt+Shift+F on any screen, then click **Add Feedback**. **Settings › Send Feedback** opens the editor without the shortcut.

`bun run build` writes the static site to `build/`, and `bun run preview` serves it.

## Post to ProcrastiMate

The dev server forwards the editor's ProcrastiMate calls to `PROCRASTIMATE_URL` and adds `PROCRASTIMATE_TOKEN`. Put a token in the root `.env.local`:

```sh
PROCRASTIMATE_TOKEN=<a ProcrastiMate API token>
```

Without a token, **ProcrastiMate** in the Share menu says that the dev server has none.
