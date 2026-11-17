import { expect, test } from 'bun:test';
import { deviceJSON, draftOf, parseSavedWebhooks, readDraft, type WebhookDraft } from './savedWebhooks.ts';

const draft = (change: Partial<WebhookDraft> = {}): WebhookDraft => ({
	...draftOf(),
	name: 'Agent',
	url: 'http://127.0.0.1:8787/feedback',
	...change,
});

test('a draft becomes a webhook with its header split, and only a JPEG keeps a compression', () => {
	expect(readDraft(draft({ header: '  Authorization:Bearer  key ' }), { id: 'w1', taken: [] })).toEqual({
		webhook: {
			id: 'w1',
			name: 'Agent',
			url: 'http://127.0.0.1:8787/feedback',
			header: { name: 'Authorization', value: 'Bearer  key' },
			image: { format: 'png' },
			feedback: true,
		},
	});
	expect(readDraft(draft({ format: 'jpeg', compression: 'high', feedback: false }), { id: 'w1', taken: [] })).toEqual({
		webhook: {
			id: 'w1',
			name: 'Agent',
			url: 'http://127.0.0.1:8787/feedback',
			image: { format: 'jpeg', compression: 'high' },
			feedback: false,
		},
	});
	expect(readDraft(draft({ image: false, format: 'jpeg' }), { id: 'w1', taken: [] })).toEqual({
		webhook: { id: 'w1', name: 'Agent', url: 'http://127.0.0.1:8787/feedback', feedback: true },
	});
});

test('a draft names each field it cannot use: no name, a name the Share menu has, an address that is not http(s), a header without a colon', () => {
	const fields = (change: Partial<WebhookDraft>, taken: string[] = []) => {
		const read = readDraft(draft(change), { id: 'w1', taken });
		return 'errors' in read ? Object.keys(read.errors) : [];
	};
	expect(fields({ name: ' ', url: 'ftp://example.com', header: 'Bearer key' })).toEqual(['name', 'url', 'header']);
	expect(fields({ url: '/feedback' })).toEqual(['url']);
	expect(fields({ name: 'github issue' }, ['GitHub Issue'])).toEqual(['name']);
});

test('editing starts from what was saved', () => {
	const saved = {
		id: 'w1',
		name: 'Agent',
		url: 'https://hooks.example.com',
		header: { name: 'X-Key', value: 'k' },
		image: { format: 'jpeg' as const, compression: 'low' as const },
		feedback: false,
	};
	const read = readDraft(draftOf(saved), { id: 'w1', taken: [] });
	expect(read).toEqual({ webhook: saved });
});

test('what the device kept is read entry by entry, and an entry it cannot use is left out', () => {
	const good = { id: 'w1', name: 'Agent', url: 'https://hooks.example.com', feedback: true };
	expect(parseSavedWebhooks(JSON.stringify([good, { id: 'w2', name: 'Bad', url: 'nope', feedback: true }, 7]))).toEqual(
		[good],
	);
	expect(parseSavedWebhooks(null)).toEqual([]);
	expect(parseSavedWebhooks('{')).toEqual([]);
	expect(parseSavedWebhooks('{"id":"w1"}')).toEqual([]);
});

test('the device part is the environment as one object with sorted keys', () => {
	expect(
		deviceJSON([
			{ name: 'App', value: 'Todo' },
			{ name: 'Device', value: 'Chrome 140 · Mac OS X' },
			{ name: 'Captured', value: '2026-11-16T19:00:00Z' },
		]),
	).toBe('{"App":"Todo","Captured":"2026-11-16T19:00:00Z","Device":"Chrome 140 · Mac OS X"}');
});
