import { expect, test } from 'bun:test';
import { githubIcon } from '../dom/webhook.ts';
import { destinations } from './destinations.ts';

const webhook = (name: string, image?: string) => ({ name, url: `/api/${name}`, image });

test('ProcrastiMate comes first, then GitHub webhooks, then the others in the app order', () => {
	const names = destinations({
		procrastimate: { url: '/procrastimate' },
		webhooks: [webhook('Slack', 'data:image/png;base64,'), webhook('Linear'), webhook('GitHub Issue', githubIcon)],
	}).map(destination => destination.name);
	expect(names).toEqual(['ProcrastiMate', 'GitHub Issue', 'Slack', 'Linear']);
});

test('without ProcrastiMate the webhooks are the destinations', () => {
	expect(destinations({ webhooks: [webhook('Linear')] }).map(destination => destination.name)).toEqual(['Linear']);
	expect(destinations({})).toEqual([]);
});
