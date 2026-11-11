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

The dev server forwards the editor's ProcrastiMate calls to `PROCRASTIMATE_URL` and adds `PROCRASTIMATE_TOKEN`. Put a token in the root `.env.local`:

```sh
PROCRASTIMATE_TOKEN=<a ProcrastiMate API token>
```

The token is the switch. With it, the Share menu lists **ProcrastiMate**. Without it, the entry is not there.
