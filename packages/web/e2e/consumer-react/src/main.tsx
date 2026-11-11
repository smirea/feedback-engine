import { setupFeedbackEngine } from '@smirea/feedback-engine/react';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';

setupFeedbackEngine({ app: 'Consumer' });

// A root that came and went. React leaves an empty marker on its container, which a capture has to step over.
const gone = document.body.appendChild(document.createElement('div'));
const short = createRoot(gone);
short.render(<p>Gone</p>);
short.unmount();

createRoot(document.getElementById('root')!).render(
	<StrictMode>
		<App />
	</StrictMode>,
);
