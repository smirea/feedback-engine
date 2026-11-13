import { afterEach, expect, test } from 'bun:test';
import worker from './worker.ts';

const env = { GITHUB_TOKEN: 'token', GITHUB_REPO: 'example/app', WEBHOOK_KEY: 'key' };
const realFetch = globalThis.fetch;
afterEach(() => {
	globalThis.fetch = realFetch;
});

type Call = { method: string; url: string; authorization: string | null; type: string | null; body: string };

/** Stands in for GitHub: keeps every request and answers as GitHub does for a repository, an upload, an issue, and a comment. */
function fakeGitHub() {
	const calls: Call[] = [];
	globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
		const request = new Request(input, init);
		const url = new URL(request.url);
		const upload = url.hostname === 'uploads.github.com';
		calls.push({
			method: request.method,
			url: request.url,
			authorization: request.headers.get('authorization'),
			type: request.headers.get('content-type'),
			body: upload ? `${(await request.arrayBuffer()).byteLength} bytes` : await request.text(),
		});
		if (upload) return Response.json({ url: 'https://github.com/user-attachments/assets/a1' }, { status: 201 });
		if (url.pathname.endsWith('/comments')) return Response.json({ id: 1 }, { status: 201 });
		if (url.pathname.endsWith('/issues')) {
			return Response.json({ number: 7, html_url: 'https://github.com/example/app/issues/7' }, { status: 201 });
		}
		return Response.json({ id: 42 });
	}) as unknown as typeof fetch;
	return calls;
}

function post(report: object, headers: Record<string, string> = { Authorization: 'Bearer key' }) {
	const form = new FormData();
	form.set('id', 'post-1');
	form.set('title', 'Lists Feedback: 2 changes');
	form.set('image', new File(['PNG'], 'feedback.png', { type: 'image/png' }));
	form.set('report', new File([JSON.stringify(report)], 'feedback.json', { type: 'application/json' }));
	return new Request('https://hooks.example.com/feedback?labels=feedback,ios', { method: 'POST', headers, body: form });
}

const report = {
	environment: [
		{ name: 'App', value: 'Todo 1.0' },
		{ name: 'Screen', value: '390 × 700' },
	],
	items: [
		{ number: 1, text: 'Row is too tall', title: 'Link "Groceries 17"', code: 'src/lib/ListRow.svelte:10' },
		{ number: 2, text: 'Wrong color\nUse the accent', title: 'Screen' },
	],
};

test('a post becomes one issue with the uploaded image, each item, and the report', async () => {
	const calls = fakeGitHub();
	const response = await worker.fetch(post(report), env);

	expect([response.status, await response.json()]).toEqual([201, { url: 'https://github.com/example/app/issues/7' }]);
	expect(response.headers.get('access-control-allow-origin')).toBe('*');
	expect(calls.map(call => [call.method, call.url, call.authorization, call.type])).toEqual([
		['GET', 'https://api.github.com/repos/example/app', 'Bearer token', null],
		[
			'POST',
			'https://uploads.github.com/user-attachments/assets?name=feedback.png&content_type=image%2Fpng&repository_id=42',
			'Bearer token',
			'application/octet-stream',
		],
		['POST', 'https://api.github.com/repos/example/app/issues', 'Bearer token', 'application/json'],
	]);
	expect(calls[1]!.body).toBe('3 bytes');
	expect(JSON.parse(calls[2]!.body)).toEqual({
		title: 'Lists Feedback: 2 changes',
		labels: ['feedback', 'ios'],
		body: [
			'![Lists Feedback: 2 changes](https://github.com/user-attachments/assets/a1)',
			'',
			'**1. Link "Groceries 17"** · `src/lib/ListRow.svelte:10`',
			'',
			'> Row is too tall',
			'',
			'**2. Screen**',
			'',
			'> Wrong color',
			'> Use the accent',
			'',
			'App: Todo 1.0 · Screen: 390 × 700',
			'',
			'<!-- feedback post post-1 -->',
			'',
			'<details>',
			'<summary>feedback.json</summary>',
			'',
			'```json',
			JSON.stringify(report),
			'```',
			'',
			'</details>',
		].join('\n'),
	});
});

test('a report too long for an issue goes into comments, in parts that join back into the file', async () => {
	const calls = fakeGitHub();
	const long = { ...report, context: [{ name: 'Store', value: 'x'.repeat(150_000) }] };
	const response = await worker.fetch(post(long), env);

	expect(response.status).toBe(201);
	expect(JSON.parse(calls[2]!.body).body.endsWith('<!-- feedback post post-1 -->')).toBe(true);
	const comments = calls.slice(3);
	expect(comments.map(call => new URL(call.url).pathname)).toEqual(
		Array(3).fill('/repos/example/app/issues/7/comments'),
	);
	const parts = comments.map(call => (JSON.parse(call.body).body as string).split('\n'));
	expect(parts.map(lines => lines[1])).toEqual([
		'<summary>feedback.json, part 1 of 3</summary>',
		'<summary>feedback.json, part 2 of 3</summary>',
		'<summary>feedback.json, part 3 of 3</summary>',
	]);
	expect(parts.map(lines => lines[4]).join('')).toBe(JSON.stringify(long));
	expect(Math.max(...comments.map(call => (JSON.parse(call.body).body as string).length))).toBeLessThan(65_536);
});

test('a post without the key, and one GitHub refuses, say why and file nothing', async () => {
	const calls = fakeGitHub();
	const unsigned = await worker.fetch(post(report, {}), env);
	expect([unsigned.status, await unsigned.json()]).toEqual([401, { message: 'The key is wrong.' }]);
	expect(calls).toEqual([]);

	globalThis.fetch = (async () =>
		Response.json({ message: 'Bad credentials' }, { status: 401 })) as unknown as typeof fetch;
	const refused = await worker.fetch(post(report), env);
	expect([refused.status, await refused.json()]).toEqual([
		502,
		{ message: 'GitHub answered 401 to GET /repos/example/app: {"message":"Bad credentials"}' },
	]);
});

test('a page on another origin gets its preflight answered', async () => {
	const response = await worker.fetch(new Request('https://hooks.example.com/feedback', { method: 'OPTIONS' }), env);
	expect([response.status, response.headers.get('access-control-allow-headers')]).toEqual([204, 'Authorization']);
});
