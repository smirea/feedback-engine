<script lang="ts">
	import { setupFeedbackEngine } from '@smirea/feedback-engine/svelte';
	import { store } from '../lib/store.svelte';
	import TabBar from '../lib/TabBar.svelte';
	import './layout.css';

	let { children } = $props();

	const feedback = setupFeedbackEngine({
		app: 'Todo',
		version: '1.0',
		procrastimate: { url: '/__feedback/procrastimate' },
	});
	feedback.context('TodoStore', () => store);
</script>

{@render children()}
<TabBar />
