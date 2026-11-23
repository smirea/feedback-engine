import { expect, test } from 'bun:test';
import { checkFiles, makeFiles } from './files.ts';

test("an app's file is its value as JSON, text, or a Blob, and one that fails or is null is left out", async () => {
	const { files, failures } = await makeFiles([
		{ name: 'save.json', data: () => ({ month: 11 }) },
		{ name: 'log.txt', data: () => 'started' },
		{ name: 'record.json', data: async () => '{"steps":[]}' },
		{ name: 'shot.webp', data: () => new Blob(['RIFF'], { type: 'image/webp' }) },
		{ name: 'lobby.json', data: () => null },
		{
			name: 'broken.json',
			data: () => {
				throw new Error('boom');
			},
		},
		{ name: 'rejected.json', data: () => Promise.reject(new Error('host left')) },
	]);
	expect(await Promise.all(files.map(async file => [file.name, file.type.split(';')[0], await file.text()]))).toEqual([
		['save.json', 'application/json', '{"month":11}'],
		['log.txt', 'text/plain', 'started'],
		['record.json', 'application/json', '{"steps":[]}'],
		['shot.webp', 'image/webp', 'RIFF'],
	]);
	expect(failures.map(failure => [failure.name, (failure.error as Error).message])).toEqual([
		['broken.json', 'boom'],
		['rejected.json', 'host left'],
	]);
});

test('a file name that would collide in a ZIP fails at setup', () => {
	expect(() => checkFiles([{ name: 'feedback.json', data: () => ({}) }])).toThrow("Feedback's own file");
	expect(() => checkFiles([{ name: 'a/b.json', data: () => ({}) }])).toThrow('plain file name');
	expect(() =>
		checkFiles([
			{ name: 'save.json', data: () => ({}) },
			{ name: 'save.json', data: () => ({}) },
		]),
	).toThrow('Two feedback files');
});
