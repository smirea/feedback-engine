import { githubIcon, setupFeedbackEngine } from '@stefan.inc/feedback-engine/react';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router';
import { App } from './App.tsx';
import { store } from './store.ts';
import './styles/layout.css';
import './styles/components.css';

const webhook: string = import.meta.env.FEEDBACK_WEBHOOK_URL;
const projects: string[] = import.meta.env.FEEDBACK_PROCRASTIMATE_PROJECTS;
const feedback = setupFeedbackEngine({
	app: 'Todo',
	version: '1.0',
	procrastimate: {
		app: import.meta.env.FEEDBACK_PROCRASTIMATE_APP,
		project: import.meta.env.FEEDBACK_PROCRASTIMATE_PROJECT || undefined,
		projects,
	},
	webhooks: webhook
		? [
				{
					name: 'GitHub Issue',
					image: githubIcon,
					url: webhook,
					// Functions run when the post is made, so the query names the page the user is on by then.
					headers: () => ({ Authorization: `Bearer ${import.meta.env.FEEDBACK_WEBHOOK_KEY}` }),
					query: () => ({ labels: 'feedback', page: location.pathname }),
				},
			]
		: [],
	pinned: ['ProcrastiMate'],
	metadata: () => ({ Lists: String(store.lists.length) }),
	files: [{ name: 'store.json', data: () => ({ lists: store.lists }) }],
});
feedback.context('TodoStore', () => store);

createRoot(document.getElementById('root')!).render(
	<StrictMode>
		<BrowserRouter>
			<App />
		</BrowserRouter>
	</StrictMode>,
);
