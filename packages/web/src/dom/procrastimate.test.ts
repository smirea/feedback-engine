import { expect, test } from 'bun:test';
import { defaultProcrastimateApp, procrastimateAppURL } from './procrastimate.ts';
import { FEEDBACK_CANCELLED, FEEDBACK_POSTED, FEEDBACK_READY, parsePopupReply } from './procrastimatePopup.ts';

test('procrastimateAppURL defaults to the hosted app and trims trailing slashes', () => {
	expect(procrastimateAppURL({ projects: ['Feedback Engine'] })).toBe(defaultProcrastimateApp);
	expect(procrastimateAppURL({ app: 'https://pm.example.com/', projects: ['Feedback Engine'] })).toBe(
		'https://pm.example.com',
	);
});

test('the popup handoff accepts only replies from the configured ProcrastiMate origin, popup window, and nonce', () => {
	const popup = {};
	const expected = { origin: 'https://procrastimate.stf.lol', source: popup, nonce: 'n-1' };
	expect(
		parsePopupReply({ origin: expected.origin, source: popup, data: { type: FEEDBACK_READY, nonce: 'n-1' } }, expected),
	).toEqual({
		kind: 'ready',
	});
	expect(
		parsePopupReply(
			{
				origin: expected.origin,
				source: popup,
				data: {
					type: FEEDBACK_POSTED,
					nonce: 'n-1',
					id: 't-1',
					destination: 'Feedback Engine',
					url: 'https://procrastimate.stf.lol/inbox?task=t-1',
				},
			},
			expected,
		),
	).toEqual({
		kind: 'posted',
		id: 't-1',
		destination: 'Feedback Engine',
		url: 'https://procrastimate.stf.lol/inbox?task=t-1',
	});
	expect(
		parsePopupReply(
			{ origin: expected.origin, source: popup, data: { type: FEEDBACK_CANCELLED, nonce: 'n-1' } },
			expected,
		),
	).toEqual({ kind: 'cancelled' });
	expect(
		parsePopupReply(
			{ origin: 'https://evil.example', source: popup, data: { type: FEEDBACK_READY, nonce: 'n-1' } },
			expected,
		),
	).toBeNull();
	expect(
		parsePopupReply({ origin: expected.origin, source: {}, data: { type: FEEDBACK_READY, nonce: 'n-1' } }, expected),
	).toBeNull();
	expect(
		parsePopupReply({ origin: expected.origin, source: popup, data: { type: FEEDBACK_READY, nonce: 'n-2' } }, expected),
	).toBeNull();
	expect(
		parsePopupReply(
			{
				origin: expected.origin,
				source: popup,
				data: { type: FEEDBACK_POSTED, nonce: 'n-1', id: 't-1', destination: 'X', url: 'javascript:alert(1)' },
			},
			expected,
		),
	).toBeNull();
});
