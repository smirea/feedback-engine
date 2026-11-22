<script lang="ts">
	import { githubIcon, setupFeedbackEngine } from '@stefan.inc/feedback-engine/svelte';
	import { store } from '../lib/store.svelte';
	import TabBar from '../lib/TabBar.svelte';
	import './layout.css';

	let { children } = $props();

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
	});
	feedback.context('TodoStore', () => store);
</script>

{@render children()}
<TabBar />
