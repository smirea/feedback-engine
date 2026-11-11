import { feedbackEngine } from '@smirea/feedback-engine/vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import { defineConfig } from 'vite';

export default defineConfig({ plugins: [svelte({ preprocess: [feedbackEngine()] })] });
