import { setupFeedbackEngine } from '@smirea/feedback-engine/react';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';

setupFeedbackEngine({ app: 'Consumer' });

createRoot(document.getElementById('root')!).render(
	<StrictMode>
		<App />
	</StrictMode>,
);
