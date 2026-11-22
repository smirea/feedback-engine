# Todo (Svelte)

The web twin of `examples/todo-ios`, for trying Feedback in a browser: lists, a list detail screen with an edit dialog and a popover menu, settings, a long timeline with sticky headers, a catalog with a carousel, and a media screen with charts and images. Every screen is tagged. It is a SvelteKit single-page app.

## Run

From the repository root:

```sh
bun install
bun run dev
```

The dev server listens on `UI_PORT` from the root `.env`, 6180 in the main checkout, and answers at http://feedback-engine.localhost when localias maps that host. An agent worktree gets its own port in `.env.local`.

Alt+Meta+click anything, which is Option+Command+click on a Mac, to open the editor on it. On a phone, **Settings › Send Feedback** starts a 5 second countdown: open the screen you mean before it ends.

`bun run build` writes the static site to `build/`, and `bun run preview` serves it.

## Post to ProcrastiMate

Choosing **ProcrastiMate** opens a popup on `PROCRASTIMATE_URL` (`/feedback`) using whoever is signed into ProcrastiMate in your browser, with no token and no proxy. Set `PROCRASTIMATE_PROJECTS` (or `PROCRASTIMATE_URL` for a local ProcrastiMate instance) in the root `.env.local` if you want to point it elsewhere.
