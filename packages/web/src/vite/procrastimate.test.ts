import { expect, test } from 'bun:test';
import { allowedProjectIds, refusal } from './procrastimate.js';

const allowed = allowedProjectIds(
	[
		{ id: 'p1', name: 'Groceries' },
		{ id: 'p2', name: 'Feedback Engine' },
	],
	['feedback engine', 'Nope'],
);
const call = (method: string, route: string, body = '', query = '') => ({
	method,
	route,
	body,
	query: new URLSearchParams(query),
});

test('the proxy creates tasks only in the listed projects, never the Inbox', () => {
	const created = new Set<string>();
	expect(refusal(call('POST', 'api/tasks', '{"projectId":"p2"}'), { allowed, created })).toBeUndefined();
	expect(refusal(call('POST', 'api/tasks', '{"projectId":"p1"}'), { allowed, created })).toBeString();
	expect(refusal(call('POST', 'api/tasks', '{"projectId":null}'), { allowed, created })).toBeString();
});

test('the proxy only attaches files to, or deletes, a task it created, and forwards nothing else', () => {
	const created = new Set(['t1']);
	const state = { allowed, created };
	expect(refusal(call('PATCH', 'api/tasks', '{"attachments":[]}', 'id=t1'), state)).toBeUndefined();
	expect(refusal(call('DELETE', 'api/tasks', '', 'id=t1'), state)).toBeUndefined();
	expect(refusal(call('PATCH', 'api/tasks', '{"attachments":[]}', 'id=t2'), state)).toBeString();
	expect(refusal(call('PATCH', 'api/tasks', '{"projectId":"p1"}', 'id=t1'), state)).toBeString();
	expect(refusal(call('DELETE', 'api/tasks', '', 'id=t2'), state)).toBeString();
	expect(refusal(call('POST', 'api/projects', '{"name":"x"}'), state)).toBeString();
	expect(refusal(call('GET', 'api/tasks'), state)).toBeString();
});
