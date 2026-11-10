# Todo (Svelte)

The web twin of `examples/todo-ios`, for trying Feedback in a browser. It is a SvelteKit SPA and has the Lists screen so far. The other screens, and the Feedback package itself, arrive with the phases in [`docs/web-plan.md`](../../docs/web-plan.md).

## Run

From the repository root:

```sh
bun install
bun run dev
```

The dev server listens on `UI_PORT` from the root `.env`, 6180 in the main checkout, and answers at http://feedback-engine.localhost when localias maps that host. An agent worktree gets its own port in `.env.local`.

`bun run build` writes the static site to `build/`, and `bun run preview` serves it.
