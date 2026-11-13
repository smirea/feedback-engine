import { expect, test } from 'bun:test';
import { withFeedbackEngine } from './index.js';

test("withFeedbackEngine keeps the app's own config and calls its webpack function", () => {
	const seen: string[] = [];
	const config = withFeedbackEngine(
		{
			reactStrictMode: true,
			transpilePackages: ['ui', '@stefan.inc/feedback-engine'],
			turbopack: { rules: { '*.svg': { loaders: ['@svgr/webpack'], as: '*.js' } } },
			webpack: (webpackConfig: { module: { rules: { test: RegExp }[] } }) => {
				seen.push(...webpackConfig.module.rules.map(rule => String(rule.test)));
				return webpackConfig;
			},
		},
		{ elementSources: true, root: '/app' },
	);
	expect(config.reactStrictMode).toBe(true);
	expect(config.transpilePackages).toEqual(['ui', '@stefan.inc/feedback-engine']);
	expect(Object.keys(config.turbopack.rules)).toEqual(['*.svg', '*.svelte', '*.{jsx,tsx}']);
	const rules = config.turbopack.rules as unknown as Record<string, { loaders: { options: object }[] }[]>;
	expect(rules['*.{jsx,tsx}']!.map(rule => rule.loaders[0]!.options)).toEqual([
		{ root: '/app', elementSources: true, generate: 'client' },
		{ root: '/app', elementSources: true, generate: 'client' },
	]);
	(config.webpack as (webpackConfig: unknown, context: unknown) => unknown)(
		{ module: { rules: [] } },
		{ dev: false, isServer: false },
	);
	expect(seen).toEqual(['/\\.svelte$/', '/\\.[jt]sx$/']);
});

test('element sources default to the dev server', () => {
	const { turbopack, webpack } = withFeedbackEngine({}, { root: '/app' }) as unknown as {
		turbopack: { rules: Record<string, { loaders: { options: { elementSources: boolean } }[] }[]> };
		webpack: (
			config: unknown,
			context: { dev: boolean; isServer: boolean },
		) => { module: { rules: { use: { options: { elementSources?: boolean } }[] }[] } };
	};
	expect(turbopack.rules['*.{jsx,tsx}']!.map(rule => rule.loaders[0]!.options.elementSources)).toEqual([true, false]);
	const sources = (dev: boolean) =>
		webpack({ module: { rules: [] } }, { dev, isServer: false }).module.rules[1]!.use[0]!.options.elementSources;
	expect([sources(true), sources(false)]).toEqual([true, false]);
});
