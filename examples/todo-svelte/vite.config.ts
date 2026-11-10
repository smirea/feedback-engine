import adapter from '@sveltejs/adapter-static';
import { sveltekit } from '@sveltejs/kit/vite';
import tailwindcss from '@tailwindcss/vite';
import env from './env.ts';
import { defineConfig } from 'vite';

const uiHost = new URL(env.UI_URL).hostname;

export default defineConfig({
	plugins: [
		tailwindcss(),
		sveltekit({
			adapter: adapter({
				fallback: 'index.html',
			}),
		}),
	],
	clearScreen: false,
	server: {
		allowedHosts: [uiHost],
		port: env.UI_PORT,
		strictPort: true,
	},
	preview: {
		allowedHosts: [uiHost],
		port: env.UI_PORT,
		strictPort: true,
	},
});
