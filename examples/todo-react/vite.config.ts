import { feedbackEngineReact, feedbackProcrastimate } from '@stefan.inc/feedback-engine/vite';
import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';
import env from '../../env.ts';

// Beside the Svelte example and the ports its browser tests use.
const port = env.UI_PORT + 5;

export default defineConfig({
	plugins: [
		tailwindcss(),
		feedbackProcrastimate({ url: env.PROCRASTIMATE_URL, token: env.PROCRASTIMATE_TOKEN }),
		feedbackEngineReact(),
		react(),
	],
	// The example reads these in the page. Vite hands a page only `VITE_` variables by itself.
	define: {
		'import.meta.env.FEEDBACK_WEBHOOK_URL': JSON.stringify(env.FEEDBACK_WEBHOOK_URL ?? ''),
		'import.meta.env.FEEDBACK_WEBHOOK_KEY': JSON.stringify(env.FEEDBACK_WEBHOOK_KEY ?? ''),
	},
	clearScreen: false,
	server: { port, strictPort: true },
	preview: { port, strictPort: true },
});
