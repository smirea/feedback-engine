import { feedbackEngineReact, feedbackProcrastimate } from '@stefan.inc/feedback-engine/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// The ProcrastiMate plugin without a token, as in an app whose environment has none. The Share menu must not list it.
export default defineConfig({ plugins: [feedbackProcrastimate({ token: undefined }), feedbackEngineReact(), react()] });
