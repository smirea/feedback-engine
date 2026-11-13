import { fileURLToPath } from 'node:url';

const loader = fileURLToPath(new URL('./loader.js', import.meta.url));
const packageName = '@stefan.inc/feedback-engine';

/**
 * Adds Feedback to a Next.js config, for Turbopack and for webpack.
 *
 * - It registers every component in the app's `.jsx` and `.tsx` files with its name and `file:line`.
 * - It compiles the editor's Svelte files.
 * - It writes each HTML element's `file:line` into a `data-feedback-source` attribute: in `next dev` by default, and in
 *   every build with `elementSources: true`.
 *
 * @template {Record<string, any>} Config
 * @param {Config} [config]
 * @param {{ elementSources?: boolean, root?: string }} [options]
 * @returns {Config}
 */
export function withFeedbackEngine(config = /** @type {Config} */ ({}), options = {}) {
	const root = options.root ?? process.cwd();
	const use = (/** @type {{ elementSources?: boolean, generate?: 'client' | 'server' }} */ settings) => ({
		loader,
		options: { root, elementSources: false, generate: 'client', ...settings },
	});

	const app = { not: 'foreign' };
	const turbopackRules = {
		'*.svelte': [
			{ condition: 'browser', loaders: [use({ generate: 'client' })], as: '*.js' },
			{ condition: { not: 'browser' }, loaders: [use({ generate: 'server' })], as: '*.js' },
		],
		'*.{jsx,tsx}': [
			{
				condition: { all: [app, 'development'] },
				loaders: [use({ elementSources: options.elementSources ?? true })],
			},
			{
				condition: { all: [app, { not: 'development' }] },
				loaders: [use({ elementSources: options.elementSources ?? false })],
			},
		],
	};
	const userWebpack = config.webpack;

	return {
		...config,
		transpilePackages: [...new Set([...(config.transpilePackages ?? []), packageName])],
		turbopack: {
			...config.turbopack,
			rules: { ...config.turbopack?.rules, ...turbopackRules },
		},
		/**
		 * @param {any} webpackConfig
		 * @param {{ dev: boolean, isServer: boolean }} context
		 */
		webpack(webpackConfig, context) {
			webpackConfig.module.rules.push(
				{ test: /\.svelte$/, use: [use({ generate: context.isServer ? 'server' : 'client' })] },
				{
					test: /\.[jt]sx$/,
					exclude: /[\\/]node_modules[\\/]/,
					enforce: 'pre',
					use: [use({ elementSources: options.elementSources ?? context.dev })],
				},
			);
			return typeof userWebpack === 'function' ? userWebpack(webpackConfig, context) : webpackConfig;
		},
	};
}
