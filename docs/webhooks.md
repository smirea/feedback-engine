# Webhooks

A webhook is an entry in the Share menu that posts the feedback to a server of yours. Choosing it sends the image export and the JSON export in one request, with nothing to fill in. What the server does with them is up to you. The main use is filing a GitHub issue, and [GitHub issues](#github-issues) has a server for that.

An app can list any number of webhooks. They appear after the built-in Share entries and ProcrastiMate. A webhook with GitHub's icon comes first, and the others follow in the order you give them. The first two of ProcrastiMate and the webhooks also get a button with their icon left of Share, so a post takes one tap.

## Set up the app

A webhook has the same five parts on every platform:

| Part | Required | Meaning |
| --- | --- | --- |
| `name` | yes | The entry's name in the Share menu, such as `GitHub Issue`. |
| `url` | yes | Where the post goes. |
| `image` | no | An icon beside the name. |
| `headers` | no | Sent with the post, such as `Authorization`. Fixed values, or a function that runs when the post is made. |
| `query` | no | Added to the URL's query. A name already in the URL is replaced. Fixed values or a function, like `headers`. |

[Authentication](#authentication) covers what to put in `headers` and `query`.

### iOS

```swift
import Feedback

Feedback.enable()
Feedback.webhooks = [
    FeedbackWebhook(
        name: "Triage",
        url: URL(string: "https://hooks.example.com/feedback")!,
        image: Image(systemName: "tray.and.arrow.down"),
        headers: ["Authorization": "Bearer \(key)"],
        query: ["app": "todo-ios"]
    ),
]
```

`image` is a SwiftUI `Image`. An entry without one shows a paper plane.

### Svelte

```svelte
<!-- src/routes/+layout.svelte -->
<script lang="ts">
	import { setupFeedbackEngine } from '@stefan.inc/feedback-engine/svelte';

	setupFeedbackEngine({
		webhooks: [
			{
				name: 'Triage',
				url: 'https://hooks.example.com/feedback',
				image: '/triage.svg',
				headers: { Authorization: `Bearer ${key}` },
				query: { app: 'todo-web' },
			},
		],
	});
</script>
```

`image` is anything an `<img>` loads: a URL, a path, or a data URL. The editor is dark, so use a light icon. A `url` that is a path, such as `/api/feedback`, is on the page's own origin.

### React

```tsx
// src/main.tsx
import { setupFeedbackEngine } from '@stefan.inc/feedback-engine/react';

setupFeedbackEngine({
	webhooks: [
		{
			name: 'Triage',
			url: 'https://hooks.example.com/feedback',
			image: '/triage.svg',
			headers: { Authorization: `Bearer ${key}` },
			query: { app: 'todo-web' },
		},
	],
});
```

### Next.js

Pass the same `webhooks` to `setupFeedbackEngine()` in the client component from the [README](../README.md#nextjs):

```tsx
// app/Feedback.tsx
'use client';

import { setupFeedbackEngine } from '@stefan.inc/feedback-engine/react';
import { useEffect } from 'react';

const webhooks = [{ name: 'Triage', url: 'https://hooks.example.com/feedback' }];

export function Feedback() {
	useEffect(() => setupFeedbackEngine({ app: 'My App', button: true, webhooks }).destroy, []);
	return null;
}
```

## Authentication

Feedback sends what you give it, and your server decides what to accept. There are three ways to tell the server who is posting.

### A fixed key

Give `headers` or `query` fixed values, as in the examples above. The key ships inside the app or the page, so anyone can read it out. Treat it as a way to turn away strangers, like an analytics write key, and not as a secret. Leave such a webhook out of a public production build, or limit how often the server accepts a post.

### The user's own session

A user is often signed out when the app starts, so a token cannot be fixed at setup. Give `headers` or `query` a function instead. It runs every time a post is made, and again on **Retry**, so it reads the session as it is by then. It can be asynchronous, for a token that has to be refreshed first.

```ts
setupFeedbackEngine({
	webhooks: [
		{
			name: 'GitHub Issue',
			url: 'https://hooks.example.com/feedback',
			headers: async () => {
				const token = await auth.token();
				if (!token) throw new Error('Sign in to send feedback.');
				return { Authorization: `Bearer ${token}` };
			},
			query: () => ({ team: auth.team }),
		},
	],
});
```

```swift
FeedbackWebhook(
    name: "GitHub Issue",
    url: URL(string: "https://hooks.example.com/feedback")!,
    headers: {
        guard let token = await auth.token() else { throw SignedOut() }
        return ["Authorization": "Bearer \(token)"]
    },
    query: { ["team": auth.team] }
)
```

What the function throws is the post's failure: the editor shows its message with **Retry**, and nothing is sent. So a signed-out user reads `Sign in to send feedback.`, signs in, and retries. On iOS the message is the error's `LocalizedError` description, and the closures run on the main actor. An iOS webhook takes either dictionaries or closures for the two, not one of each.

### Cookies

On the web, a `url` on the page's own origin, such as `/api/feedback`, gets the page's cookies from the browser, so a server that already knows the user by a session cookie needs nothing in `headers`. A `url` on another origin gets no cookies. Use a header there.

## The request

Every platform sends the same request: one `POST` to `url`, with `query` in its query string, `headers` among its headers, and a `multipart/form-data` body with four parts.

| Part | Kind | Contents |
| --- | --- | --- |
| `id` | text | A UUID made for this post. **Retry** sends the same one, so a server can tell a retry from a second post. |
| `title` | text | The screen's name, `Feedback`, and the item count, such as `Lists Feedback: 2 changes`. |
| `image` | file `feedback.png`, `image/png` | The [image export](../spec/report.md#image-export). |
| `report` | file `feedback.json`, `application/json` | The [JSON export](../spec/report.md#json-export), minified. |

The same request from a shell, to try a server without an app:

```sh
curl https://hooks.example.com/feedback \
  -H 'Authorization: Bearer some-key' \
  -F id=test-1 \
  -F 'title=Lists Feedback: 1 change' \
  -F 'image=@feedback.png;type=image/png' \
  -F 'report=@feedback.json;type=application/json'
```

## The answer

- Any `2xx` status means the post landed. The editor shows a toast, **Sent to** and the webhook's name, and the items count as shared.
- A JSON body with a `url`, such as `{ "url": "https://github.com/owner/name/issues/7" }`, makes the toast a link to what the server made. Only an `http` or `https` address is used.
- Any other status is a failure. A JSON body with a `message` is shown after the webhook's name, such as `GitHub Issue: GitHub answered 401.` Without one the editor shows the status. The request, the status, and the response are under **Details**, and **Copy Error** copies them.

A failed post stays in the editor with **Retry**. It is not kept after the editor closes: a post made without a connection has to be sent again.

## From a browser

A page usually posts to a webhook on another origin, so the server has to allow it:

- Answer every response with `Access-Control-Allow-Origin`, or the page cannot read the answer and the post counts as failed.
- A webhook with `headers` makes the browser send an `OPTIONS` request first. Answer it with `Access-Control-Allow-Headers` naming those headers.

A webhook without `headers` needs no `OPTIONS` answer. To keep a key and skip that request, put the key in `query`. iOS has none of these rules.

## GitHub issues

`examples/github-webhook/worker.ts` is a webhook server that files every post as an issue in one repository:

- The image export is uploaded to GitHub and shown at the top of the issue.
- Each item follows with its number, its target, the `file:line`, and its text.
- The environment is one line under the items.
- `feedback.json` is in a collapsed block at the end, so an agent that reads the issue has the whole report. A report too long for an issue's body goes into comments instead, in numbered parts.
- A `labels` query parameter, such as `labels=feedback,ios`, labels the issue.

The server answers with the issue's address, so the toast opens the issue.

### The token

The server needs a GitHub token that can write to the repository. The image goes through the upload endpoint that the GitHub CLI's `--attach` flag uses, and that endpoint is what sets these rules:

- The token's account needs write access to the repository. Read access gets a 404.
- The CLI's own token (`gh auth token`) works. GitHub's changelog names classic personal access tokens too, with the `repo` scope. Fine-grained tokens and GitHub App tokens were not tried.
- It works on github.com, not on GitHub Enterprise Server.
- GitHub does not document the endpoint as an API, so it can change.

Every issue is opened by the token's account, whoever gave the feedback. A bot account with write access keeps them apart from your own.

### Run it on your machine

```sh
GITHUB_TOKEN=$(gh auth token) GITHUB_REPO=owner/name WEBHOOK_KEY=some-key ./examples/github-webhook/serve.ts
```

It listens on port 8787, or `PORT`. With `WEBHOOK_KEY` set, a post must send `Authorization: Bearer some-key`. Leave it out to accept every post. An iOS simulator reaches it at `http://127.0.0.1:8787`.

### Run it as a Cloudflare Worker

Set `GITHUB_REPO` in `examples/github-webhook/wrangler.toml`, then:

```sh
cd examples/github-webhook
bunx wrangler secret put GITHUB_TOKEN
bunx wrangler secret put WEBHOOK_KEY
bunx wrangler deploy
```

`bunx wrangler dev` runs it locally in the Workers runtime. The server is one `fetch` handler that uses nothing but web requests, so any runtime that has them can host it.

### Point the app at it

Both packages ship GitHub's mark for the entry's icon.

iOS:

```swift
Feedback.webhooks = [
    FeedbackWebhook(
        name: "GitHub Issue",
        url: URL(string: "https://feedback-github-webhook.example.workers.dev")!,
        image: Feedback.githubIcon,
        headers: ["Authorization": "Bearer some-key"],
        query: ["labels": "feedback,ios"]
    ),
]
```

Svelte, React, and Next.js, with `githubIcon` from the entry point the app already imports:

```ts
import { githubIcon, setupFeedbackEngine } from '@stefan.inc/feedback-engine/svelte'; // or '/react'

setupFeedbackEngine({
	webhooks: [
		{
			name: 'GitHub Issue',
			url: 'https://feedback-github-webhook.example.workers.dev',
			image: githubIcon,
			headers: { Authorization: 'Bearer some-key' },
			query: { labels: 'feedback,web' },
		},
	],
});
```

### Try it in the example apps

The web examples read `FEEDBACK_WEBHOOK_URL` and `FEEDBACK_WEBHOOK_KEY`. Put them in `.env.local` and run `bun run dev` or `bun run dev:react`:

```sh
FEEDBACK_WEBHOOK_URL=http://127.0.0.1:8787
FEEDBACK_WEBHOOK_KEY=some-key
```

The iOS example reads the same two names from its launch environment. `simctl` passes a variable to the app when its name starts with `SIMCTL_CHILD_`:

```sh
cd examples/todo-ios
SIMCTL_CHILD_FEEDBACK_WEBHOOK_URL=http://127.0.0.1:8787 SIMCTL_CHILD_FEEDBACK_WEBHOOK_KEY=some-key ./scripts/run -t simulator
```

Without a URL, the examples have no **GitHub Issue** entry.

## Write your own server

A server reads the form and answers with JSON. This one accepts a post from any origin and links the toast to a page of its own:

```ts
export default {
	async fetch(request: Request): Promise<Response> {
		const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Authorization' };
		if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });

		const form = await request.formData();
		const title = form.get('title') as string;
		const image = form.get('image') as File;
		const report = JSON.parse(await (form.get('report') as File).text());
		const id = await save(form.get('id') as string, title, image, report);

		return Response.json({ url: `https://triage.example.com/feedback/${id}` }, { headers: cors });
	},
};
```

`save` stands for whatever your server does with the post. [spec/report.md](../spec/report.md#json-export) lists what `report` holds.
