import { setupFeedbackEngine } from '@smirea/feedback-engine/react';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router';
import { App } from './App.tsx';
import { store } from './store.ts';
import './styles/layout.css';
import './styles/components.css';

const feedback = setupFeedbackEngine({ app: 'Todo', version: '1.0' });
feedback.context('TodoStore', () => store);

createRoot(document.getElementById('root')!).render(
	<StrictMode>
		<BrowserRouter>
			<App />
		</BrowserRouter>
	</StrictMode>,
);
