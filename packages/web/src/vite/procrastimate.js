/** What `setupFeedbackEngine()` reads. `editor/setup.ts` spells the same names. */
const pathDefine = 'import.meta.env.FEEDBACK_PROCRASTIMATE';
const projectDefine = 'import.meta.env.FEEDBACK_PROCRASTIMATE_PROJECT';
const projectsDefine = 'import.meta.env.FEEDBACK_PROCRASTIMATE_PROJECTS';

/**
 * @typedef {{ id: string, name: string }} Project
 * @typedef {{ projects: Project[], sections: { id: string, projectId: string }[] }} View
 */

/**
 * The ids of the projects `names` lists, each by id or by name ignoring case, as the picker matches them.
 *
 * @param {Project[]} projects
 * @param {string[]} names
 */
export function allowedProjectIds(projects, names) {
	/** @type {Set<string>} */
	const ids = new Set();
	for (const name of names) {
		const project =
			projects.find(candidate => candidate.id === name) ??
			projects.find(candidate => candidate.name.toLowerCase() === name.toLowerCase());
		if (project) ids.add(project.id);
	}
	return ids;
}

/**
 * Why the proxy refuses a call, or `undefined` to forward it. The token can do anything in the space, so the proxy
 * forwards only the calls a post makes: listing the projects, uploading its files, creating a task in an allowed
 * project, and attaching the files to, or deleting, a task this proxy created.
 *
 * @param {{ method: string, route: string, query: URLSearchParams, body: string }} call
 * @param {{ allowed?: Set<string>, created: Set<string> }} state `allowed` is needed only to create a task.
 */
export function refusal({ method, route, query, body }, { allowed, created }) {
	const key = `${method} ${route}`;
	if (key === 'GET api/view' || key === 'PUT api/images') return;
	if (key === 'POST api/tasks') {
		/** @type {{ projectId?: string | null }} */
		let task;
		try {
			task = JSON.parse(body);
		} catch {
			return 'the task is not JSON';
		}
		if (!task.projectId || !allowed?.has(task.projectId))
			return 'Feedback posts only to the projects feedbackProcrastimate({ projects }) lists';
		return;
	}
	if (key === 'PATCH api/tasks' || key === 'DELETE api/tasks') {
		const id = query.get('id');
		if (!id || !created.has(id)) return 'Feedback changes only the tasks it created';
		if (method === 'PATCH') {
			try {
				if (Object.keys(JSON.parse(body)).some(field => field !== 'attachments'))
					return 'Feedback only attaches files to a task it created';
			} catch {
				return 'the change is not JSON';
			}
		}
		return;
	}
	return `Feedback does not forward ${method} /${route}`;
}

/**
 * The view with only the allowed projects and their sections, which is all the picker reads.
 *
 * @param {View} view
 * @param {Set<string>} allowed
 */
export const allowedView = (view, allowed) => ({
	projects: view.projects.filter(project => allowed.has(project.id)),
	sections: view.sections.filter(section => allowed.has(section.projectId)),
});

/**
 * A Vite plugin that lets the page post to ProcrastiMate. A browser on another origin cannot call ProcrastiMate, and a
 * token in the page would be public, so the dev and preview servers forward `path` to ProcrastiMate and add the
 * token there.
 *
 * The token is the switch. With one, the plugin tells the page where the proxy is, and the Share menu lists
 * ProcrastiMate. Without one the page is told nothing, so the entry is not there. A page that names the path itself
 * then gets a 501 that says why.
 *
 * @param {{ url?: string, token?: string, path?: string, project?: string, projects: string[] }} options
 */
export function feedbackProcrastimate(options) {
	if (!options?.projects?.length)
		throw new Error(
			'feedbackProcrastimate({ projects }) needs the ProcrastiMate projects Feedback may post to, by name or id.',
		);
	const { projects } = options;
	const path = options.path ?? '/__feedback/procrastimate';
	const target = (options.url ?? 'https://procrastimate.stf.lol').replace(/\/$/, '');
	/** @type {Set<string>} */
	const created = new Set();

	/** @param {string} route @param {RequestInit} [init] */
	const upstream = (route, init = {}) =>
		fetch(`${target}/${route}`, {
			...init,
			headers: { Authorization: `Bearer ${options.token}`, 'User-Agent': 'Feedback', ...init.headers },
		});

	/** @type {import('vite').Connect.NextHandleFunction} */
	const handler = (request, response, next) => {
		if (!request.url?.startsWith(`${path}/`)) return next();
		const reply = (/** @type {number} */ status, /** @type {string} */ message) => {
			response.statusCode = status;
			response.setHeader('Content-Type', 'application/json');
			response.end(JSON.stringify({ message }));
		};
		if (!options.token)
			return reply(501, 'the dev server has no ProcrastiMate token. Pass one to feedbackProcrastimate().');
		const forward = async () => {
			const chunks = [];
			for await (const chunk of request) chunks.push(chunk);
			const body = Buffer.concat(chunks);
			const method = request.method ?? 'GET';
			const relative = /** @type {string} */ (request.url).slice(path.length + 1);
			const url = new URL(relative, 'http://proxy/');
			const route = url.pathname.slice(1);
			const send = async (/** @type {Response} */ answer, /** @type {Buffer} */ bytes) => {
				response.statusCode = answer.status;
				response.setHeader('Content-Type', answer.headers.get('content-type') ?? 'application/json');
				response.end(bytes);
			};
			const view = async () => {
				const answer = await upstream('api/view');
				if (!answer.ok) return { answer };
				const data = /** @type {View} */ (await answer.json());
				return { answer, data, allowed: allowedProjectIds(data.projects, projects) };
			};

			if (method === 'GET' && route === 'api/view') {
				const { answer, data, allowed } = await view();
				if (!data) return send(answer, Buffer.from(await answer.arrayBuffer()));
				response.setHeader('Content-Type', 'application/json');
				return response.end(JSON.stringify(allowedView(data, allowed)));
			}
			const creates = method === 'POST' && route === 'api/tasks';
			let allowed;
			if (creates) {
				const listed = await view();
				if (!listed.data) return send(listed.answer, Buffer.from(await listed.answer.arrayBuffer()));
				allowed = listed.allowed;
			}
			const why = refusal({ method, route, query: url.searchParams, body: body.toString() }, { allowed, created });
			if (why) return reply(403, why);
			const answer = await upstream(relative, {
				method,
				headers: request.headers['content-type'] ? { 'Content-Type': request.headers['content-type'] } : {},
				body: body.length ? body : undefined,
			});
			const bytes = Buffer.from(await answer.arrayBuffer());
			if (answer.ok && creates) created.add(/** @type {{ id: string }} */ (JSON.parse(bytes.toString())).id);
			if (answer.ok && method === 'DELETE') created.delete(url.searchParams.get('id') ?? '');
			send(answer, bytes);
		};
		forward().catch(error =>
			reply(502, `the dev server could not reach ${target}: ${/** @type {Error} */ (error).message}`),
		);
	};
	return {
		name: 'feedback-engine-procrastimate',
		config() {
			return {
				define: {
					[pathDefine]: JSON.stringify(options.token ? path : ''),
					[projectDefine]: JSON.stringify(options.project ?? ''),
					[projectsDefine]: JSON.stringify(JSON.stringify(projects)),
				},
			};
		},
		/** @param {import('vite').ViteDevServer} server */
		configureServer(server) {
			server.middlewares.use(handler);
		},
		/** @param {import('vite').PreviewServer} server */
		configurePreviewServer(server) {
			server.middlewares.use(handler);
		},
	};
}
