import { expect, test } from 'bun:test';
import { defaultProcrastimateApp, procrastimateAppURL } from './procrastimate.ts';
import {
	FEEDBACK_CANCELLED,
	FEEDBACK_POSTED,
	FEEDBACK_READY,
	isRealPopup,
	parsePopupReply,
} from './procrastimatePopup.ts';

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

test('isRealPopup rejects null, closed windows, and popup-blocker stubs while accepting real fresh, same-origin, and cross-origin windows', () => {
	const pm = 'https://procrastimate.stf.lol';
	const app = 'https://pandemic-legacy-s2.stf.lol';

	expect(isRealPopup(null, pm, app)).toBe(false);
	expect(
		isRealPopup({ closed: true, [Symbol.toStringTag]: 'Window', location: { href: 'about:blank' } }, pm, app),
	).toBe(false);
	expect(isRealPopup({ closed: false, location: { href: `${pm}/feedback?nonce=1` } }, pm, app)).toBe(false);
	expect(
		isRealPopup(
			{ closed: false, [Symbol.toStringTag]: 'Window', location: { href: `${pm}/feedback?nonce=1` } },
			pm,
			app,
		),
	).toBe(false);

	expect(
		isRealPopup({ closed: false, [Symbol.toStringTag]: 'Window', location: { href: 'about:blank' } }, pm, app),
	).toBe(true);
	expect(
		isRealPopup(
			{ closed: false, [Symbol.toStringTag]: 'Window', location: { href: `${pm}/feedback?nonce=1` } },
			pm,
			pm,
		),
	).toBe(true);
	const crossOriginProxy = {
		closed: false,
		location: {
			get href(): string {
				throw new DOMException('Blocked a frame with origin', 'SecurityError');
			},
		},
	};
	expect(isRealPopup(crossOriginProxy, pm, app)).toBe(true);
});
