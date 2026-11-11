import { feedbackEngineReact } from '@smirea/feedback-engine/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({ plugins: [feedbackEngineReact(), react()] });
