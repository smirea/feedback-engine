import { realpathSync } from 'node:fs';
import { relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseSync } from 'oxc-parser';
import { compile } from 'svelte/compiler';

const entry = '@smirea/feedback-engine/react';
/** The same name as `sourceAttribute` in `dom/tags.ts`. Node cannot import that file from `node_modules`, so a test compares the two. */
export const sourceAttribute = 'data-feedback-source';
/** The package's own source folder. Only its Svelte files are compiled, and its modules are never registered. */
export const packageSource = realpathSync(fileURLToPath(new URL('..', import.meta.url))) + sep;

/**
 * Compiles one of the editor's Svelte files to JavaScript, with its styles in the code, for a React app's bundler.
 *
 * @param {string} code
 * @param {string} file
 * @param {'client' | 'server'} generate
 */
export function compileEditor(code, file, generate) {
	const { js } = compile(code, { filename: file, css: 'injected', generate });
	return js;
}

const wrappers = new Set(['TSAsExpression', 'TSSatisfiesExpression', 'TSNonNullExpression', 'ParenthesizedExpression']);
const values = new Set(['ArrowFunctionExpression', 'FunctionExpression', 'ClassExpression', 'CallExpression']);

/**
 * Whether a variable's value can be a component: a function, a class, or a call such as `memo(...)`. A call that
 * returns something else is registered too, and never matches anything React renders.
 *
 * @param {any} init
 */
function canBeComponent(init) {
	let value = init;
	while (value && wrappers.has(value.type)) value = value.expression;
	return Boolean(value) && values.has(value.type);
}

const named = (/** @type {any} */ id) => id?.type === 'Identifier' && /^[A-Z]/.test(id.name);

/**
 * Prepares a React module for feedback captures.
 *
 * - Registers every component the module declares at its top level, with its name and `file:line`. React keeps a
 *   component's name only as the function's name, which a minified build replaces, and has no record of where a
 *   component came from. Being registered is also what tells the app's components from a library's.
 * - Rewrites each `feedback(` call to `feedback.at("file:line")(`, as the Svelte preprocessor does.
 * - With `elementSources`, gives every HTML element its `file:line` in an attribute. React 19 no longer records it.
 *
 * Every edit stays on its line, so the module's line numbers hold without a source map.
 *
 * @param {string} code
 * @param {string} file The module's path from the project root.
 * @param {{ elementSources?: boolean }} [options]
 * @returns {string | undefined} The new source, or `undefined` when nothing changed or the module does not parse.
 */
export function addReact(code, file, options = {}) {
	const { program, errors } = parseSync(file, code);
	if (errors.length) return;
	// A server functions module may export only async functions, and a registration call is not one.
	if (program.body[0]?.type === 'ExpressionStatement' && program.body[0].directive === 'use server') return;

	const lineStarts = [0];
	for (let index = code.indexOf('\n'); index !== -1; index = code.indexOf('\n', index + 1)) lineStarts.push(index + 1);
	const where = (/** @type {number} */ offset) => {
		let low = 0;
		let high = lineStarts.length - 1;
		while (low < high) {
			const middle = (low + high + 1) >> 1;
			if (lineStarts[middle] <= offset) low = middle;
			else high = middle - 1;
		}
		return `${file}:${low + 1}`;
	};

	/** @type {[name: string, source: string][]} */
	const components = [];
	/** @type {Set<string>} */
	const locals = new Set();
	for (const statement of /** @type {any[]} */ (program.body)) {
		if (statement.type === 'ImportDeclaration' && statement.source.value === entry) {
			for (const specifier of statement.specifiers) {
				if (specifier.type === 'ImportSpecifier' && specifier.imported.name === 'feedback')
					locals.add(specifier.local.name);
			}
		}
		const declaration = /^Export(Named|Default)Declaration$/.test(statement.type) ? statement.declaration : statement;
		if (!declaration || declaration.declare) continue;
		if (/^(Function|Class)Declaration$/.test(declaration.type) && named(declaration.id) && declaration.body) {
			components.push([declaration.id.name, where(declaration.id.start)]);
		}
		for (const { id, init } of declaration.type === 'VariableDeclaration' ? declaration.declarations : []) {
			if (named(id) && canBeComponent(init)) components.push([id.name, where(id.start)]);
		}
	}

	/** @type {{ at: number, text: string }[]} */
	const edits = [];
	const visit = (/** @type {any} */ node) => {
		if (!node || typeof node !== 'object') return;
		if (Array.isArray(node)) return node.forEach(visit);
		if (node.type === 'CallExpression' && node.callee.type === 'Identifier' && locals.has(node.callee.name)) {
			edits.push({ at: node.callee.end, text: `.at(${JSON.stringify(where(node.start))})` });
		}
		if (
			options.elementSources &&
			node.type === 'JSXOpeningElement' &&
			node.name.type === 'JSXIdentifier' &&
			/^[a-z]/.test(node.name.name) &&
			!node.attributes.some((/** @type {any} */ attribute) => attribute.name?.name === sourceAttribute)
		) {
			edits.push({ at: node.name.end, text: ` ${sourceAttribute}={${JSON.stringify(where(node.start))}}` });
		}
		for (const key in node) if (key !== 'type') visit(node[key]);
	};
	visit(program.body);

	if (!edits.length && !components.length) return;
	let changed = code;
	for (const edit of edits.toSorted((a, b) => b.at - a.at))
		changed = changed.slice(0, edit.at) + edit.text + changed.slice(edit.at);
	if (!components.length) return changed;
	const calls = components.map(
		([name, source]) => `register(${name}, ${JSON.stringify(name)}, ${JSON.stringify(source)});`,
	);
	// A value that is not a function or an object cannot be a component, and a WeakMap would throw on it.
	return `${changed}\n;(register => { ${calls.join(' ')} })((component, name, source) => { if (typeof component === 'function' || (typeof component === 'object' && component !== null)) (globalThis.__feedbackComponents ??= new WeakMap()).set(component, [name, source]); });\n`;
}

/**
 * The Vite plugin for a React app. Put it before the React plugin.
 *
 * - It runs `addReact` on the app's `.jsx` and `.tsx` modules, so a capture finds the app's components by name.
 * - It compiles the editor, which is written in Svelte, so the app needs no Svelte plugin of its own.
 *
 * @param {{ elementSources?: boolean }} [options] `elementSources` defaults to the dev server only, and never in tests.
 */
export function feedbackEngineReact(options = {}) {
	let root = process.cwd();
	let elementSources = false;
	return {
		name: 'feedback-engine-react',
		enforce: /** @type {const} */ ('pre'),
		// Pre-bundling would meet the editor's Svelte files without this plugin to compile them.
		config: () => ({ optimizeDeps: { exclude: ['@smirea/feedback-engine'] } }),
		/** @param {import('vite').ResolvedConfig} config */
		configResolved(config) {
			root = config.root;
			elementSources = options.elementSources ?? (config.command === 'serve' && config.mode !== 'test');
		},
		transform: {
			filter: { id: /\.(svelte|jsx|tsx)(\?.*)?$/ },
			/**
			 * @param {string} code
			 * @param {string} id
			 * @param {{ ssr?: boolean }} [transformOptions]
			 */
			handler(code, id, transformOptions) {
				const file = id.split('?')[0];
				if (file.endsWith('.svelte')) {
					if (!file.startsWith(packageSource)) return;
					const js = compileEditor(code, file, transformOptions?.ssr ? 'server' : 'client');
					return { code: js.code, map: js.map };
				}
				if (file.includes('/node_modules/') || file.startsWith(packageSource)) return;
				const changed = addReact(code, relative(root, file).split(sep).join('/'), { elementSources });
				return changed === undefined ? undefined : { code: changed, map: null };
			},
		},
	};
}
