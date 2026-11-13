import { feedbackEngine } from '@stefan.inc/feedback-engine/vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import { defineConfig } from 'vite';

export default defineConfig({ plugins: [svelte({ preprocess: [feedbackEngine()] })] });
