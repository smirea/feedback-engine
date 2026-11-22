import { feedbackEngineReact, feedbackProcrastimate } from '@stefan.inc/feedback-engine/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// The ProcrastiMate plugin without a token, as in an app whose environment has none.
export default defineConfig({
	plugins: [feedbackProcrastimate({ token: undefined, projects: ['Feedback'] }), feedbackEngineReact(), react()],
});
