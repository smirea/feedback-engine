import { expect, test } from 'bun:test';
import { listedProjects, startingProject, type Project } from './procrastimate.ts';
import { FEEDBACK_CANCELLED, FEEDBACK_POSTED, FEEDBACK_READY, parsePopupReply } from './procrastimatePopup.ts';

const project = (id: string, name: string): Project => ({ id, name, sections: [] });
const all = [project('p1', 'Groceries'), project('p2', 'Feedback Engine'), project('p3', 'Garden')];
const ids = (projects: Project[]) => projects.map(({ id }) => id);

test('the picker lists only the named projects, in the app order, and reports names ProcrastiMate lacks', () => {
	const listed = listedProjects(all, ['feedback engine', 'Nope', 'p1', 'Groceries']);
	expect(ids(listed.projects)).toEqual(['p2', 'p1']);
	expect(listed.missing).toEqual(['Nope']);
});

test('the picker never starts on the Inbox', () => {
	const config = { url: '', projects: ['Garden', 'Groceries'] };
	const listed = listedProjects(all, config.projects).projects;
	expect(startingProject(listed, config, 'p2')).toBe('p3');
	expect(startingProject(listed, config, 'p1')).toBe('p1');
	expect(startingProject(listed, config, undefined)).toBe('p3');
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
