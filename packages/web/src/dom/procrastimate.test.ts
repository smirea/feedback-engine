import { expect, test } from 'bun:test';
import { listedProjects, startingProject, type Project } from './procrastimate.ts';

const project = (id: string, name: string): Project => ({ id, name, sections: [] });
const all = [project('p1', 'Groceries'), project('p2', 'Feedback Engine'), project('p3', 'Garden')];
const ids = (projects: Project[]) => projects.map(({ id }) => id);

test('a project whitelist lists only the named projects, in its order, and reports names ProcrastiMate lacks', () => {
	const listed = listedProjects(all, ['feedback engine', 'Nope', 'p1', 'Groceries']);
	expect(ids(listed.projects)).toEqual(['p2', 'p1']);
	expect(listed.missing).toEqual(['Nope']);
	expect(ids(listedProjects(all, undefined).projects)).toEqual(['p1', 'p2', 'p3']);
});

test('with a whitelist the picker never starts on the Inbox', () => {
	const listed = listedProjects(all, ['Garden', 'Groceries']).projects;
	expect(startingProject(listed, { url: '', projects: ['Garden', 'Groceries'] }, 'p2')).toBe('p3');
	expect(startingProject(listed, { url: '', projects: ['Garden', 'Groceries'] }, 'p1')).toBe('p1');
	expect(startingProject(all, { url: '' }, undefined)).toBeUndefined();
});
