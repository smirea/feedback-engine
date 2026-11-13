import { basename, relative, sep } from 'node:path';
import { parse } from 'svelte/compiler';

export { addReact, feedbackEngineReact, sourceAttribute } from './react.js';

const entry = '@stefan.inc/feedback-engine/svelte';

/** What `setupFeedbackEngine()` reads for the proxy's path. `editor/setup.ts` spells the same name. */
const procrastimateDefine = 'import.meta.env.FEEDBACK_PROCRASTIMATE';

/**
 * The name a tag gets without one: the file's, as `.feedback(self)` uses the type's on iOS. A SvelteKit route file is
 * named after its folder, so `routes/lists/[id]/+page.svelte` is `ListsIdPage`.
 *
 * @param {string} file
 */
export function componentName(file) {
	const pascal = (/** @type {string} */ text) =>
		text
			.split(/[^\p{L}\p{N}]+/u)
			.filter(Boolean)
			.map(word => word[0].toUpperCase() + word.slice(1))
			.join('');
	const stem = basename(file).replace(/\.svelte$/, '');
	if (!stem.startsWith('+')) return pascal(stem) || 'Component';
	const folders = file.split('/').slice(0, -1);
	const routes = folders.lastIndexOf('routes');
	return pascal([...folders.slice(routes + 1), stem].join(' '));
}

/**
 * The names a bare `feedback()` reports, as `.feedback(self)` reports a view's stored properties and state on iOS: the
 * component's props, and the variables it declares with `$state`.
 *
 * @param {any} instance The component's instance script.
 * @returns {string[]}
 */
function dataNames(instance) {
	/** @type {string[]} */
	const names = [];
	for (const statement of instance?.content.body ?? []) {
		if (statement.type !== 'VariableDeclaration') continue;
		for (const { id, init } of statement.declarations) {
			if (init?.type !== 'CallExpression') continue;
			const callee = init.callee.type === 'MemberExpression' ? init.callee.object : init.callee;
			if (callee.type !== 'Identifier') continue;
			if (callee.name === '$state' && id.type === 'Identifier') names.push(id.name);
			if (callee.name !== '$props') continue;
			if (id.type === 'Identifier') names.push(`...${id.name}`);
			for (const property of id.type === 'ObjectPattern' ? id.properties : []) {
				if (property.type !== 'Property') continue;
				const value = property.value.type === 'AssignmentPattern' ? property.value.left : property.value;
				if (value.type === 'Identifier') names.push(value.name);
			}
		}
	}
	return names;
}

/**
 * Finds every `{@attach feedback(...)}` in a component and rewrites the call to `feedback.at("file:line", "Name")(...)`.
 * JavaScript has no `#fileID` and `#line`, so the location is written in at build time. A call without arguments also
 * gets the component's props and state as its data.
 *
 * @param {string} content
 * @param {string} file The component's path from the project root.
 * @returns {string | undefined} The new source, or `undefined` when nothing changed.
 */
export function addLocations(content, file) {
	if (!content.includes(entry)) return;
	const ast = parse(content, { modern: true, filename: file });
	/** @type {Set<string>} */
	const locals = new Set();
	for (const script of [ast.instance, ast.module]) {
		for (const node of script?.content.body ?? []) {
			if (node.type !== 'ImportDeclaration' || node.source.value !== entry) continue;
			for (const specifier of node.specifiers) {
				if (
					specifier.type === 'ImportSpecifier' &&
					specifier.imported.type === 'Identifier' &&
					specifier.imported.name === 'feedback'
				) {
					locals.add(specifier.local.name);
				}
			}
		}
	}
	if (!locals.size) return;

	/** @type {{ at: number, text: string }[]} */
	const edits = [];
	const name = JSON.stringify(componentName(file));
	const names = dataNames(ast.instance);
	const data = names.length ? `, () => ({ ${names.join(', ')} })` : '';
	const visit = (/** @type {any} */ node) => {
		if (!node || typeof node !== 'object') return;
		if (Array.isArray(node)) return node.forEach(visit);
		if (node.type === 'AttachTag') {
			const call = node.expression;
			if (call.type === 'CallExpression' && call.callee.type === 'Identifier' && locals.has(call.callee.name)) {
				const line = content.slice(0, call.start).split('\n').length;
				const bare = call.arguments.length === 0 ? data : '';
				edits.push({ at: call.callee.end, text: `.at(${JSON.stringify(`${file}:${line}`)}, ${name}${bare})` });
			}
			return;
		}
		for (const key of [
			'fragment',
			'nodes',
			'attributes',
			'consequent',
			'alternate',
			'body',
			'fallback',
			'pending',
			'then',
			'catch',
		]) {
			visit(node[key]);
		}
	};
	visit(ast.fragment);
	if (!edits.length) return;
	let code = content;
	for (const edit of edits.toSorted((a, b) => b.at - a.at))
		code = code.slice(0, edit.at) + edit.text + code.slice(edit.at);
	return code;
}

/**
 * A Svelte preprocessor that gives every `feedback()` tag its `file:line` and a default name. Add it to the
 * preprocessors of the Svelte or SvelteKit Vite plugin.
 *
 * @param {{ root?: string }} [options] `root` is the folder paths are written from. Defaults to the working directory.
 */
export function feedbackEngine(options = {}) {
	const root = options.root ?? process.cwd();
	return {
		name: 'feedback-engine',
		/** @param {{ content: string, filename?: string }} input */
		markup({ content, filename }) {
			if (!filename || filename.includes('node_modules')) return;
			const code = addLocations(content, relative(root, filename).split(sep).join('/'));
			return code === undefined ? undefined : { code };
		},
	};
}

/**
 * A Vite plugin that lets the page post to ProcrastiMate. A browser on another origin cannot call ProcrastiMate, and a
 * token in the page would be public, so the dev and preview servers forward `path` to ProcrastiMate and add the
 * token there.
 *
 * The token is the switch. With one, the plugin tells the page where the proxy is, and the Share menu lists
 * ProcrastiMate. Without one the page is told nothing, so the entry is not there. A page that names the path itself
 * then gets a 501 that says why.
 *
 * @param {{ url?: string, token?: string, path?: string }} [options]
 */
export function feedbackProcrastimate(options = {}) {
	const path = options.path ?? '/__feedback/procrastimate';
	const target = (options.url ?? 'https://procrastimate.stf.lol').replace(/\/$/, '');
	/** @type {import('vite').Connect.NextHandleFunction} */
	const handler = async (request, response, next) => {
		if (!request.url?.startsWith(`${path}/`)) return next();
		const reply = (/** @type {number} */ status, /** @type {string} */ message) => {
			response.statusCode = status;
			response.setHeader('Content-Type', 'application/json');
			response.end(JSON.stringify({ message }));
		};
		if (!options.token)
			return reply(501, 'the dev server has no ProcrastiMate token. Pass one to feedbackProcrastimate().');
		try {
			const chunks = [];
			for await (const chunk of request) chunks.push(chunk);
			const body = Buffer.concat(chunks);
			const upstream = await fetch(target + request.url.slice(path.length), {
				method: request.method,
				headers: {
					Authorization: `Bearer ${options.token}`,
					'User-Agent': 'Feedback',
					...(request.headers['content-type'] ? { 'Content-Type': request.headers['content-type'] } : {}),
				},
				body: body.length ? body : undefined,
			});
			response.statusCode = upstream.status;
			response.setHeader('Content-Type', upstream.headers.get('content-type') ?? 'application/json');
			response.end(Buffer.from(await upstream.arrayBuffer()));
		} catch (error) {
			reply(502, `the dev server could not reach ${target}: ${/** @type {Error} */ (error).message}`);
		}
	};
	return {
		name: 'feedback-engine-procrastimate',
		config() {
			return { define: { [procrastimateDefine]: JSON.stringify(options.token ? path : '') } };
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
