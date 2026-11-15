import type { ProcrastimateConfig } from '../dom/procrastimate.ts';
import { procrastimateIcon } from '../dom/procrastimate-icon.ts';
import { githubIcon, type Webhook } from '../dom/webhook.ts';

/** A server the feedback can be posted to, as the Share menu lists it after the exports. */
export type Destination = { name: string; image?: string } & (
	| { kind: 'procrastimate' }
	| { kind: 'webhook'; webhook: Webhook }
);

/** ProcrastiMate first, then the webhooks with GitHub's icon, then the other webhooks in the app's order. */
export function destinations(options: { procrastimate?: ProcrastimateConfig; webhooks?: Webhook[] }): Destination[] {
	const webhooks = [...(options.webhooks ?? [])].sort(
		(a, b) => Number(b.image === githubIcon) - Number(a.image === githubIcon),
	);
	return [
		...(options.procrastimate
			? [{ kind: 'procrastimate' as const, name: 'ProcrastiMate', image: procrastimateIcon }]
			: []),
		...webhooks.map(webhook => ({ kind: 'webhook' as const, name: webhook.name, image: webhook.image, webhook })),
	];
}

/**
 * The destinations that also get a button beside Share: the ones `pinned` names, in its order, or the first two
 * without it. A name with no destination is skipped, since a webhook can join the list after setup.
 */
export function pinnedDestinations(all: Destination[], pinned: string[] | undefined): Destination[] {
	if (!pinned) return all.slice(0, 2);
	return pinned.flatMap(name => all.filter(destination => destination.name === name));
}
