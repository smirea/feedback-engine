import { setupFeedbackEngine } from '@smirea/feedback-engine/svelte';
import { mount } from 'svelte';
import App from './App.svelte';

setupFeedbackEngine({ app: 'Consumer', shortcut: 'Alt+Shift+F' });
mount(App, { target: document.getElementById('app') });
