import { afterEach, expect, test } from 'bun:test';
import { postWebhook, savedDelivery, type Webhook } from './webhook.ts';

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

const post = {
	id: 'post-1',
	title: 'Lists Feedback: 1 change',
	files: [
		{ name: 'image', file: new File(['PNG'], 'feedback.png', { type: 'image/png' }) },
		{ name: 'report', file: new File(['{}'], 'feedback.json', { type: 'application/json' }) },
	],
};

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

test('a saved webhook sends its one header, and the parts in their order after the id and the title', async () => {
	const sent: { form?: FormData; authorization?: string | null } = {};
	globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
		const request = new Request(input, init);
		sent.authorization = request.headers.get('authorization');
		sent.form = await request.formData();
		return new Response(null, { status: 204 });
	}) as unknown as typeof fetch;
	const { webhook, contents } = savedDelivery({
		id: 'saved-1',
		name: 'Agent',
		url: 'http://127.0.0.1:8787/feedback',
		header: { name: 'Authorization', value: 'Bearer key' },
		image: { format: 'jpeg', compression: 'high' },
		feedback: false,
	});
	expect(contents).toEqual({ kind: 'saved', image: { format: 'jpeg', compression: 'high' }, feedback: false });

	const files = [
		{ name: 'image', file: new File(['JPEG'], 'feedback.jpg', { type: 'image/jpeg' }) },
		{ name: 'device', file: new File(['{}'], 'device.json', { type: 'application/json' }) },
	];
	expect(await postWebhook(webhook, { id: 'post-1', title: 'Lists Feedback: 1 change', files })).toBeUndefined();
	expect(sent.authorization).toBe('Bearer key');
	expect([...sent.form!.keys()]).toEqual(['id', 'title', 'image', 'device']);
	expect((sent.form!.get('image') as File).name).toBe('feedback.jpg');
});
