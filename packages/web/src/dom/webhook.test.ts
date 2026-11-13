import { afterEach, expect, test } from 'bun:test';
import { postWebhook, type Webhook } from './webhook.ts';

const realFetch = globalThis.fetch;
afterEach(() => {
	globalThis.fetch = realFetch;
});

// `postWebhook` resolves a path against the page, and Bun has no page.
Object.assign(globalThis, { location: { href: 'https://app.example.com/lists' } });

/** Stands in for the webhook's server: keeps each request's address and `Authorization`, and answers with a link. */
function server() {
	const requests: { url: string; authorization: string | null }[] = [];
	globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
		const request = new Request(input, init);
		requests.push({ url: request.url, authorization: request.headers.get('authorization') });
		return Response.json({ url: 'https://github.com/example/app/issues/7' });
	}) as unknown as typeof fetch;
	return requests;
}

const post = { id: 'post-1', title: 'Lists Feedback: 1 change', image: new Blob(['PNG']), report: '{}' };

test('a function for headers or query runs for every post, so a retry sends what is true by then', async () => {
	const requests = server();
	let token: string | undefined;
	const webhook: Webhook = {
		name: 'GitHub Issue',
		url: '/api/feedback?labels=old',
		headers: async () => {
			if (!token) throw new Error('Sign in to send feedback.');
			return { Authorization: `Bearer ${token}` };
		},
		query: () => ({ labels: 'feedback', user: token ?? 'nobody' }),
	};

	await expect(postWebhook(webhook, post)).rejects.toThrow('Sign in to send feedback.');
	expect(requests).toEqual([]);

	token = 'first';
	expect(await postWebhook(webhook, post)).toBe('https://github.com/example/app/issues/7');
	token = 'second';
	await postWebhook(webhook, post);
	expect(requests).toEqual([
		{ url: 'https://app.example.com/api/feedback?labels=feedback&user=first', authorization: 'Bearer first' },
		{ url: 'https://app.example.com/api/feedback?labels=feedback&user=second', authorization: 'Bearer second' },
	]);
});

test('fixed headers and query go out as they are', async () => {
	const requests = server();
	await postWebhook(
		{
			name: 'Triage',
			url: 'https://hooks.example.com/feedback',
			headers: { Authorization: 'Bearer key' },
			query: { app: 'todo' },
		},
		post,
	);
	expect(requests).toEqual([{ url: 'https://hooks.example.com/feedback?app=todo', authorization: 'Bearer key' }]);
});
