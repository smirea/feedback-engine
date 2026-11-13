<script lang="ts">
	import { feedback } from '@stefan.inc/feedback-engine/svelte';
	import { page } from '$app/state';

	const tabs = [
		{ href: '/', name: 'Lists' },
		{ href: '/settings', name: 'Settings' },
	];
	const current = (href: string) =>
		href === '/' ? !page.url.pathname.startsWith('/settings') : page.url.pathname.startsWith(href);
</script>

<nav class="tabs" aria-label="Tabs" {@attach feedback()}>
	{#each tabs as tab (tab.href)}
		<a href={tab.href} aria-current={current(tab.href) ? 'page' : undefined}>{tab.name}</a>
	{/each}
</nav>

<style>
	.tabs {
		position: fixed;
		right: 0;
		bottom: 0;
		left: 0;
		display: flex;
		justify-content: center;
		gap: 0.5rem;
		border-top: 1px solid var(--app-border);
		padding: 0.5rem 1rem max(0.5rem, env(safe-area-inset-bottom));
		background: var(--app-panel);
	}

	a {
		border-radius: 0.5rem;
		padding: 0.5rem 1.5rem;
		color: var(--app-muted);
		font-weight: 600;
		text-decoration: none;
	}

	a[aria-current='page'] {
		background: var(--app-bg);
		color: var(--app-accent);
	}
</style>
