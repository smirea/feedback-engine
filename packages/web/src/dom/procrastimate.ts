export type ProcrastimateConfig = {
	/** Where ProcrastiMate's API answers: the Vite plugin's proxy path, or a server that allows this origin. */
	url: string;
	/** Sent as a bearer token. Leave it out behind the proxy, which adds its own. */
	token?: string;
	/** The ProcrastiMate web app, for the link to a posted task. */
	app?: string;
};

export type Section = { id: string; name: string };
export type Project = { id: string; name: string; sections: Section[] };
/** Where a task goes: the Inbox without a project, and the project's top, above its sections, without a section. */
export type Place = { projectId?: string; sectionId?: string };

/** ProcrastiMate's `FILE_PART_BYTES` and `FILE_MAX_BYTES` (`shared/images.ts` there). */
const filePartBytes = 1_500_000;
const fileMaxBytes = 25_000_000;
const defaultApp = 'https://procrastimate.stf.lol';

const projectsKey = 'feedback.procrastimate.projects';
const lastProjectKey = 'feedback.procrastimate.project';

function stored<T>(key: string): T | undefined {
	try {
		const value = localStorage.getItem(key);
		return value === null ? undefined : (JSON.parse(value) as T);
	} catch {
		return undefined;
	}
}

const store = (key: string, value: unknown) => {
	try {
		if (value === undefined) localStorage.removeItem(key);
		else localStorage.setItem(key, JSON.stringify(value));
	} catch {
		// Storage can be off, as in a private window. The picker then opens empty.
	}
};

/** The projects from the last time the picker loaded them, so it opens filled. */
export const cachedProjects = () => stored<Project[]>(projectsKey) ?? [];
/** The project of the last post. Its section is not kept, so a new post starts at the project's top. */
export const lastProject = () => stored<string>(lastProjectKey);

export const taskLink = (config: ProcrastimateConfig, id: string) =>
	`${(config.app ?? defaultApp).replace(/\/$/, '')}/inbox?task=${encodeURIComponent(id)}`;

async function send(
	config: ProcrastimateConfig,
	method: string,
	path: string,
	query: Record<string, string> = {},
	body?: BodyInit,
	type?: string,
) {
	const search = new URLSearchParams(Object.entries(query).toSorted(([a], [b]) => a.localeCompare(b)));
	const response = await fetch(`${config.url.replace(/\/$/, '')}/${path}${search.size ? `?${search}` : ''}`, {
		method,
		body,
		headers: {
			...(config.token ? { Authorization: `Bearer ${config.token}` } : {}),
			...(type ? { 'Content-Type': type } : {}),
		},
	});
	if (response.status === 401)
		throw new Error('ProcrastiMate rejected the token. Check the token Feedback was set up with.');
	if (!response.ok) {
		const message = await response
			.json()
			.then(data => (data as { message?: string }).message)
			.catch(() => undefined);
		throw new Error(message ? `ProcrastiMate: ${message}` : `ProcrastiMate answered ${response.status}.`);
	}
	return response;
}

type Row = { id: string; name: string; order: number; createdAt: number };
const inOrder = <T extends Row>(rows: T[]) => rows.toSorted((a, b) => a.order - b.order || a.createdAt - b.createdAt);

/** The space's projects and their sections in the app's order. `/api/view` is the only route that lists them. */
export async function loadProjects(config: ProcrastimateConfig): Promise<Project[]> {
	const view = (await (await send(config, 'GET', 'api/view')).json()) as {
		projects: Row[];
		sections: (Row & { projectId: string })[];
	};
	const projects = inOrder(view.projects).map(project => ({
		id: project.id,
		name: project.name,
		sections: inOrder(view.sections.filter(section => section.projectId === project.id)).map(({ id, name }) => ({
			id,
			name,
		})),
	}));
	store(projectsKey, projects);
	return projects;
}

type Encoded = { blob: Blob; width: number; height: number };

/**
 * A JPEG of the image no wider than `width` and no larger than `maxBytes`. ProcrastiMate's own clients fit the long
 * side. A full-length capture is many times taller than wide, so this fits the width, which keeps its text readable.
 */
async function jpeg(image: HTMLCanvasElement, width: number, maxBytes: number): Promise<Encoded> {
	for (let target = Math.min(width, image.width); target >= 64; target = Math.floor((target * 3) / 4)) {
		const scaled = document.createElement('canvas');
		scaled.width = target;
		scaled.height = Math.max(1, Math.round((image.height * target) / image.width));
		const context = scaled.getContext('2d')!;
		context.imageSmoothingQuality = 'high';
		context.drawImage(image, 0, 0, scaled.width, scaled.height);
		for (const quality of [0.8, 0.65, 0.5]) {
			const blob = await new Promise<Blob | null>(resolve => scaled.toBlob(resolve, 'image/jpeg', quality));
			if (blob && blob.size <= maxBytes) return { blob, width: scaled.width, height: scaled.height };
		}
	}
	throw new Error('The image could not be made small enough to upload.');
}

/**
 * Creates one task with the image export and `feedback.json` attached, and returns its id. The attachments upload
 * before the task that lists them, as ProcrastiMate's own clients do, so the task never names bytes the server
 * cannot serve.
 */
export async function postTask(
	config: ProcrastimateConfig,
	title: string,
	place: Place,
	image: HTMLCanvasElement,
	report: string,
) {
	const bytes = new TextEncoder().encode(report);
	if (bytes.length > fileMaxBytes) throw new Error("The JSON report is over ProcrastiMate's 25 MB file limit.");
	const full = await jpeg(image, 2048, 1_500_000);
	const thumb = await jpeg(image, 320, 200_000);
	const imageId = crypto.randomUUID();
	const reportId = crypto.randomUUID();
	await send(config, 'PUT', 'api/images', { id: imageId, size: 'full' }, full.blob, 'image/jpeg');
	await send(config, 'PUT', 'api/images', { id: imageId, size: 'thumb' }, thumb.blob, 'image/jpeg');
	for (let start = 0, part = 0; start < bytes.length; start += filePartBytes, part++) {
		const chunk = bytes.slice(start, start + filePartBytes);
		await send(config, 'PUT', 'api/images', { id: reportId, size: `part${part}` }, chunk, 'application/octet-stream');
	}
	const created = await send(
		config,
		'POST',
		'api/tasks',
		{},
		JSON.stringify({ title, projectId: place.projectId ?? null, sectionId: place.sectionId ?? null }),
		'application/json',
	);
	const { id } = (await created.json()) as { id: string };
	// The agent API cannot create a task with attachments, so a failed attach would leave a task without them, and a retry would add a second one.
	try {
		await send(
			config,
			'PATCH',
			'api/tasks',
			{ id },
			JSON.stringify({
				attachments: [
					{ id: imageId, width: full.width, height: full.height },
					{ id: reportId, name: 'feedback.json', type: 'application/json', bytes: bytes.length },
				],
			}),
			'application/json',
		);
	} catch (error) {
		await send(config, 'DELETE', 'api/tasks', { id }).catch(() => {});
		throw error;
	}
	store(lastProjectKey, place.projectId);
	return id;
}
