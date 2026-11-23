import type { Annotations } from '../core/annotations.ts';
import { Problem, type Fact } from '../core/problem.ts';
import type { Screen } from './capture.ts';
import { annotatedImage } from './image.ts';
import { encodeTaskImages, fileMaxBytes, procrastimateAppURL, type ProcrastimateConfig } from './procrastimate.ts';
import { postId } from './webhook.ts';

export const FEEDBACK_READY = 'feedback:ready';
export const FEEDBACK_DRAFT = 'feedback:draft';
export const FEEDBACK_POSTED = 'feedback:posted';
export const FEEDBACK_CANCELLED = 'feedback:cancelled';

export type PopupReply =
	| { kind: 'ready' }
	| { kind: 'posted'; id: string; destination: string; url: string }
	| { kind: 'cancelled' };

function isHttpURL(value: unknown): value is string {
	if (typeof value !== 'string') return false;
	try {
		const parsed = new URL(value);
		return parsed.protocol === 'http:' || parsed.protocol === 'https:';
	} catch {
		return false;
	}
}

/**
 * Validates a message posted back from ProcrastiMate's `/feedback` popup. Every message must come from the configured
 * ProcrastiMate origin, from the popup window we opened, and carry this handoff's nonce.
 */
export function parsePopupReply(
	event: { origin: string; source: unknown; data: unknown },
	expected: { origin: string; source: unknown; nonce: string },
): PopupReply | null {
	if (event.origin !== expected.origin || event.source !== expected.source) return null;
	const data = event.data;
	if (!data || typeof data !== 'object') return null;
	const record = data as Record<string, unknown>;
	if (record.nonce !== expected.nonce) return null;
	if (record.type === FEEDBACK_READY) return { kind: 'ready' };
	if (record.type === FEEDBACK_CANCELLED) return { kind: 'cancelled' };
	if (
		record.type === FEEDBACK_POSTED &&
		typeof record.id === 'string' &&
		typeof record.destination === 'string' &&
		isHttpURL(record.url)
	) {
		return { kind: 'posted', id: record.id, destination: record.destination, url: record.url };
	}
	return null;
}

function popupFeatures() {
	const width = 460;
	const height = 680;
	const scr = window.screen as { availLeft?: number; availTop?: number };
	const rawLeft = Math.round((window.screenX ?? 0) + (window.outerWidth - width) / 2);
	const rawTop = Math.round((window.screenY ?? 0) + (window.outerHeight - height) / 2);
	const left = scr.availLeft === undefined ? rawLeft : Math.max(scr.availLeft, rawLeft);
	const top = scr.availTop === undefined ? rawTop : Math.max(scr.availTop, rawTop);
	return `popup,width=${width},height=${height},left=${left},top=${top}`;
}

/**
 * Distinguishes a real browser WindowProxy from `null`, an already-closed window, or a plain JS stub returned by a
 * popup-blocker extension (which sets `location.href` synchronously and leaves `closed: false` forever).
 */
export function isRealPopup(popup: unknown, expectedOrigin: string, currentOrigin: string): popup is Window {
	if (!popup || (typeof popup !== 'object' && typeof popup !== 'function')) return false;
	const candidate = popup as Window;
	try {
		if (candidate.closed) return false;
	} catch {
		return false;
	}
	let href: string;
	try {
		href = candidate.location.href;
	} catch {
		// Reading `location.href` threw a cross-origin SecurityError: only a real browser WindowProxy enforces that.
		return true;
	}
	if (Object.prototype.toString.call(candidate) !== '[object Window]') return false;
	if (expectedOrigin !== currentOrigin && typeof href === 'string' && href.startsWith(expectedOrigin)) return false;
	return true;
}

/**
 * Runs `action` on the shadow host's light-DOM click bubble when the click originated inside a shadow root.
 * Per the DOM spec, browsers clear `window.event` while an event dispatches inside a shadow tree, which causes popup
 * blockers that inspect `window.event.currentTarget` (such as Poper Blocker) to treat a real button click as having no
 * user interaction. Waiting one synchronous propagation step onto `root.host` restores `window.event` within the same
 * click gesture.
 */
export function runOnLightClick(event: MouseEvent | undefined, action: () => void) {
	if (!event || !event.bubbles || !event.composed || event.cancelBubble) {
		action();
		return;
	}
	const path = event.composedPath();
	const root = (path[0] as Node | undefined)?.getRootNode?.();
	if (!(root instanceof ShadowRoot) || !path.includes(root.host)) {
		action();
		return;
	}
	let ran = false;
	const host = root.host;
	const onHostClick = (bubbled: Event) => {
		if (bubbled !== event || ran) return;
		ran = true;
		host.removeEventListener(event.type, onHostClick);
		action();
	};
	host.addEventListener(event.type, onHostClick);
	// Macrotask, not microtask: browsers drain microtasks between each listener in an event's bubble path.
	setTimeout(() => {
		if (!ran) host.removeEventListener(event.type, onHostClick);
	}, 0);
}

/**
 * Opens ProcrastiMate's `/feedback` popup synchronously (so the browser's click gesture allows `window.open`) while
 * encoding the screenshot in parallel, then hands over the draft over `postMessage` once the popup signals ready.
 * No credential ever leaves ProcrastiMate's own origin.
 */
export function openProcrastimatePopup({
	config,
	title,
	app,
	screen,
	annotations,
	report,
	onposted,
	onerror,
	onclose,
}: {
	config: ProcrastimateConfig;
	title: string;
	app?: string;
	screen: Screen;
	annotations: Annotations;
	report: string;
	onposted: (result: { id: string; destination: string; url: string }) => void;
	onerror: (problem: Problem) => void;
	onclose?: () => void;
}): { cancel: () => void } {
	const base = procrastimateAppURL(config);
	const expectedOrigin = new URL(base, location.href).origin;
	const nonce = postId();
	const url = `${base}/feedback?nonce=${encodeURIComponent(nonce)}`;
	const environment: Fact[] = screen.capture.environment.map(entry => ({ label: entry.name, value: entry.value }));
	const reportBytes = new TextEncoder().encode(report).byteLength;
	if (reportBytes > fileMaxBytes) {
		onerror(
			Problem.from(new Error('The JSON report is over the 16 MB ProcrastiMate takes in one upload.')).with(
				[{ label: 'Report', value: `${reportBytes} bytes` }],
				environment,
			),
		);
		return { cancel() {} };
	}

	const popup = window.open(url, 'feedback-procrastimate', popupFeatures());
	if (!isRealPopup(popup, expectedOrigin, location.origin)) {
		onerror(
			new Problem('The browser blocked ProcrastiMate’s window. Allow pop-ups for this site and try again.', [
				{ label: 'URL', value: url },
				...environment,
			]),
		);
		return { cancel() {} };
	}
	try {
		popup.focus();
	} catch {
		// Some browsers restrict focusing a popup window.
	}

	// Render synchronously before any await; encode JPEGs while the popup loads.
	let prepared: Promise<{ full: Blob; thumb: Blob; width: number; height: number }>;
	try {
		const canvas = annotatedImage(screen, annotations);
		prepared = encodeTaskImages(canvas).then(({ full, thumb }) => ({
			full: full.blob,
			thumb: thumb.blob,
			width: full.width,
			height: full.height,
		}));
	} catch (error) {
		prepared = Promise.reject(error);
	}
	// Prevent an unhandled rejection if the user closes the popup before encoding settles.
	prepared.catch(() => {});

	let done = false;
	const cleanup = () => {
		if (done) return;
		done = true;
		window.removeEventListener('message', onMessage);
		clearInterval(closedCheck);
	};

	const onMessage = (event: MessageEvent) => {
		const reply = parsePopupReply(event, { origin: expectedOrigin, source: popup, nonce });
		if (!reply) return;
		if (reply.kind === 'ready') {
			void prepared
				.then(image => {
					if (done || popup.closed) return;
					popup.postMessage(
						{
							type: FEEDBACK_DRAFT,
							nonce,
							title,
							app,
							project: config.project,
							projects: config.projects,
							space: config.space,
							image,
							report,
						},
						expectedOrigin,
					);
				})
				.catch((error: unknown) => {
					cleanup();
					try {
						popup.close();
					} catch {
						// Ignore if already closed.
					}
					onerror(
						Problem.from(error).with(
							[
								{ label: 'Step', value: 'Encoding the image' },
								{ label: 'URL', value: url },
							],
							environment,
						),
					);
				});
			return;
		}
		cleanup();
		if (reply.kind === 'posted') onposted(reply);
		else onclose?.();
	};

	window.addEventListener('message', onMessage);
	const closedCheck = setInterval(() => {
		if (popup.closed) {
			cleanup();
			onclose?.();
		}
	}, 400);

	return { cancel: cleanup };
}
