import { feedbackEngineReact, feedbackProcrastimate } from '@smirea/feedback-engine/vite';
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
	clearScreen: false,
	server: { port, strictPort: true },
	preview: { port, strictPort: true },
});
