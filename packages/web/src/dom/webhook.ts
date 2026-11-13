import { Problem } from '../core/problem.ts';

/** One entry of the Share menu that posts the feedback to a server of the app's own. `docs/webhooks.md` has the request. */
export type Webhook = {
	/** The entry's name in the Share menu, such as `GitHub Issue`. */
	name: string;
	/** Where the post goes. A path, such as `/api/feedback`, is on the page's own origin. */
	url: string;
	/** An icon beside the name: anything an `<img>` loads, such as `githubIcon` or a data URL. */
	image?: string;
	/** Sent with the post, such as `Authorization`. Whatever a page sends is public. */
	headers?: Record<string, string>;
	/** Added to the URL's query. */
	query?: Record<string, string>;
};

export type WebhookPost = {
	/** Made once per post and sent again on a retry, so a server can tell a retry from a second post. */
	id: string;
	title: string;
	/** The image export, as PNG. */
	image: Blob;
	/** The JSON export. */
	report: string;
};

/**
 * GitHub's mark in white, for a webhook that files issues. The iOS package draws the same path
 * (`GitHubIcon.swift`), which has only absolute `M`, `L`, `C`, and `Z` commands so that a few lines can read it.
 */
export const githubIcon = `data:image/svg+xml,${encodeURIComponent(
	'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="white"><path d="M6.766 11.328C4.703 11.078 3.25 9.594 3.25 7.672C3.25 6.891 3.531 6.047 4 5.484C3.797 4.969 3.828 3.875 4.063 3.422C4.688 3.344 5.531 3.672 6.031 4.125C6.625 3.938 7.25 3.844 8.016 3.844C8.781 3.844 9.406 3.938 9.969 4.109C10.453 3.672 11.313 3.344 11.938 3.422C12.156 3.844 12.188 4.937 11.984 5.469C12.484 6.062 12.75 6.859 12.75 7.672C12.75 9.594 11.297 11.047 9.203 11.312C9.734 11.656 10.093 12.406 10.093 13.266L10.093 14.891C10.093 15.359 10.484 15.625 10.953 15.438C13.781 14.359 16 11.53 16 8.03C16 3.61 12.406 0 7.984 0C3.563 0 0 3.61 0 8.031C-0.009 11.347 2.058 14.314 5.172 15.453C5.594 15.609 6 15.328 6 14.906L6 13.656C5.781 13.75 5.5 13.812 5.25 13.812C4.219 13.812 3.61 13.25 3.172 12.203C3 11.781 2.812 11.531 2.453 11.484C2.266 11.469 2.203 11.391 2.203 11.297C2.203 11.109 2.516 10.969 2.828 10.969C3.281 10.969 3.672 11.25 4.078 11.829C4.391 12.281 4.718 12.484 5.109 12.484C5.5 12.484 5.75 12.344 6.109 11.984C6.375 11.719 6.579 11.484 6.766 11.328Z"/></svg>',
)}`;

/** `crypto.randomUUID` exists only in a secure context, and a phone often opens a dev server over plain HTTP. */
export function postId() {
	if (crypto.randomUUID) return crypto.randomUUID();
	const bytes = crypto.getRandomValues(new Uint8Array(16));
	bytes[6] = (bytes[6]! & 0x0f) | 0x40;
	bytes[8] = (bytes[8]! & 0x3f) | 0x80;
	const hex = [...bytes].map(byte => byte.toString(16).padStart(2, '0')).join('');
	return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/**
 * Sends one post and returns the link the server answered with, if any, for the toast. The link is the server's to
 * choose, so only a web address is kept: the toast opens it.
 */
export async function postWebhook(webhook: Webhook, post: WebhookPost): Promise<string | undefined> {
	const url = new URL(webhook.url, location.href);
	for (const [name, value] of Object.entries(webhook.query ?? {})) url.searchParams.set(name, value);
	const form = new FormData();
	form.set('id', post.id);
	form.set('title', post.title);
	form.set('image', new File([post.image], 'feedback.png', { type: 'image/png' }));
	form.set('report', new File([post.report], 'feedback.json', { type: 'application/json' }));
	let response: Response;
	try {
		response = await fetch(url, { method: 'POST', headers: webhook.headers, body: form });
	} catch (error) {
		throw Problem.request('POST', url.href, undefined, undefined, error);
	}
	const text = await response.text().catch(() => '');
	let answer: { url?: unknown; message?: unknown } = {};
	try {
		const parsed: unknown = JSON.parse(text);
		if (parsed && typeof parsed === 'object') answer = parsed;
	} catch {
		// An empty answer, or a proxy's HTML error page, which the details show as it came.
	}
	if (!response.ok) {
		const message =
			typeof answer.message === 'string'
				? `${webhook.name}: ${answer.message}`
				: `${webhook.name} answered ${response.status}.`;
		throw Problem.request('POST', url.href, response.status, text, new Error(message));
	}
	if (typeof answer.url !== 'string' || !URL.canParse(answer.url)) return undefined;
	return /^https?:$/.test(new URL(answer.url).protocol) ? answer.url : undefined;
}
