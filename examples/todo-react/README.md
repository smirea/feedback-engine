# Todo (React)

The React twin of `examples/todo-svelte`, for trying Feedback in a browser: lists, a list detail screen with an edit dialog and a popover menu, settings, a long timeline with sticky headers, a catalog with a carousel, and a media screen with charts and images. It is a Vite app with React 19 and React Router.

No component is tagged for its name. `feedbackEngineReact()` in `vite.config.ts` registers every component, and a capture finds them in React's own tree. The `feedback(...)` refs do the two jobs that are left:

- They name a region drawn inline, such as `ProgressHeader` and `SortMenu` in `src/screens/ListDetailScreen.tsx`.
- They report state under the component's own name, such as the draft in `src/components/TodoDetailDialog.tsx`.

## Run

From the repository root:

```sh
bun install
bun run dev:react
```

The dev server listens on `UI_PORT + 5`, with `UI_PORT` from the root `.env`: 6185 in the main checkout. An agent worktree gets its own port in `.env.local`.

Alt+Meta+click anything, which is Option+Command+click on a Mac, to open the editor on it. On a phone, **Settings › Send Feedback** starts a 5 second countdown: open the screen you mean before it ends.

`bun run build` writes both example apps, this one to `dist/`, and `bun run preview:react` serves it.

## Post to ProcrastiMate

Choosing **ProcrastiMate** opens a popup on `PROCRASTIMATE_URL` (`/feedback`) using whoever is signed into ProcrastiMate in your browser, with no token and no proxy. Set `PROCRASTIMATE_PROJECTS` (or `PROCRASTIMATE_URL` for a local ProcrastiMate instance) in the root `.env.local` if you want to point it elsewhere.
