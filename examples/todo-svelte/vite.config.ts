import adapter from '@sveltejs/adapter-static';
import { sveltekit } from '@sveltejs/kit/vite';
import tailwindcss from '@tailwindcss/vite';
import { feedbackEngine, feedbackProcrastimate } from '@smirea/feedback-engine/vite';
import env from '../../env.ts';
import { defineConfig } from 'vite';

const uiHost = new URL(env.UI_URL).hostname;

export default defineConfig({
	plugins: [
		tailwindcss(),
		feedbackProcrastimate({ url: env.PROCRASTIMATE_URL, token: env.PROCRASTIMATE_TOKEN }),
		sveltekit({
			preprocess: [feedbackEngine()],
			adapter: adapter({
				fallback: 'index.html',
			}),
		}),
	],
	// The example reads these in the page. Vite hands a page only `VITE_` variables by itself.
	define: {
		'import.meta.env.FEEDBACK_WEBHOOK_URL': JSON.stringify(env.FEEDBACK_WEBHOOK_URL ?? ''),
		'import.meta.env.FEEDBACK_WEBHOOK_KEY': JSON.stringify(env.FEEDBACK_WEBHOOK_KEY ?? ''),
	},
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
