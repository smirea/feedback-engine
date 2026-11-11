import { setupFeedbackEngine } from '@smirea/feedback-engine/svelte';
import { mount } from 'svelte';
import App from './App.svelte';

setupFeedbackEngine({ app: 'Consumer' });
mount(App, { target: document.getElementById('app') });
