<svelte:options css="injected" />

<script lang="ts">
	import { taskTitle, type FeedbackItem, type Session, type Toast } from '../core/index.ts';
	import type { Screen } from '../dom/capture.ts';
	import { annotatedImage } from '../dom/image.ts';
	import {
		cachedProjects,
		lastProject,
		loadProjects,
		postTask,
		taskLink,
		type Place,
		type ProcrastimateConfig,
	} from '../dom/procrastimate.ts';

	let {
		screen,
		session,
		config,
		onclose,
		onposted,
	}: {
		screen: Screen;
		session: Session;
		config: ProcrastimateConfig;
		onclose: () => void;
		onposted: (items: FeedbackItem[], toast: Toast) => void;
	} = $props();

	// svelte-ignore state_referenced_locally
	const names = taskTitle(session.capture, session.items);
	let name = $state(names.placeholder);
	let projects = $state(cachedProjects());
	let place = $state<Place>({ projectId: lastProject() });
	let loading = $state(true);
	let loadError = $state<string>();
	let postError = $state<string>();
	let posting = $state(false);

	$effect(() => {
		loadProjects(config)
			.then(loaded => {
				projects = loaded;
				const project = loaded.find(candidate => candidate.id === place.projectId);
				if (!project) place = {};
				else if (!project.sections.some(section => section.id === place.sectionId)) place = { projectId: project.id };
			})
			.catch((error: Error) => (loadError = error.message))
			.finally(() => (loading = false));
	});

	async function post() {
		posting = true;
		postError = undefined;
		const items = [...session.items];
		const project = projects.find(candidate => candidate.id === place.projectId);
		const section = project?.sections.find(candidate => candidate.id === place.sectionId);
		try {
			const id = await postTask(
				config,
				name.trim(),
				place,
				annotatedImage(screen, session.annotations),
				session.compactJSON,
			);
			const destination = [project?.name ?? 'Inbox', section?.name].filter(Boolean).join(' / ');
			onposted(items, { text: `Added to ${destination} in ProcrastiMate`, link: taskLink(config, id) });
		} catch (error) {
			postError = (error as Error).message;
			posting = false;
		}
	}
</script>

{#snippet row(label: string, picked: boolean, indented: boolean, pick: () => void)}
	<button
		type="button"
		class="row"
		class:indented
		role="option"
		aria-selected={picked}
		disabled={posting}
		onclick={pick}
	>
		<span>{label}</span>
		{#if picked}<span class="check" aria-hidden="true">✓</span>{/if}
	</button>
{/snippet}

<div class="scrim" role="presentation">
	<form
		class="sheet"
		aria-label="Add to ProcrastiMate"
		onsubmit={event => {
			event.preventDefault();
			void post();
		}}
	>
		<header>
			<button type="button" class="link" disabled={posting} onclick={onclose}>Cancel</button>
			<h2>Add to ProcrastiMate</h2>
			<button type="submit" class="link strong" disabled={posting || !name.trim()}>{posting ? 'Adding…' : 'Add'}</button
			>
		</header>
		<div class="scroll">
			<label>
				<span class="caption">Name</span>
				<input bind:value={name} aria-label="Task name" disabled={posting} />
			</label>
			<span class="caption">Project{loading ? ' · loading…' : ''}</span>
			<div class="list" role="listbox" aria-label="Project">
				{@render row('Inbox', !place.projectId, false, () => (place = {}))}
				{#each projects as project (project.id)}
					{@const open = project.id === place.projectId && project.sections.length > 0}
					{@render row(
						project.name,
						project.id === place.projectId && !open,
						false,
						() => (place = { projectId: project.id }),
					)}
					{#if open}
						{@render row('No section', !place.sectionId, true, () => (place = { projectId: project.id }))}
						{#each project.sections as section (section.id)}
							{@render row(
								section.name,
								place.sectionId === section.id,
								true,
								() => (place = { projectId: project.id, sectionId: section.id }),
							)}
						{/each}
					{/if}
				{/each}
			</div>
			{#if loadError}<p class="error">{loadError}</p>{/if}
			{#if postError}<p class="error" role="alert">{postError}</p>{/if}
		</div>
	</form>
</div>

<style>
	.scrim {
		position: absolute;
		inset: 0;
		z-index: 5;
		display: grid;
		place-items: end center;
		background: rgb(0 0 0 / 0.5);
	}

	.sheet {
		display: flex;
		flex-direction: column;
		width: min(100%, 480px);
		max-height: 85%;
		border-radius: 16px 16px 0 0;
		box-sizing: border-box;
		background: #1f1f1f;
	}

	header {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 14px 16px 8px;
	}

	h2 {
		flex: 1;
		margin: 0;
		font-size: 16px;
		text-align: center;
	}

	button,
	input {
		color: inherit;
		font: inherit;
	}

	button {
		border: 0;
		background: none;
		cursor: pointer;
	}

	button:disabled {
		cursor: default;
		opacity: 0.5;
	}

	.link {
		color: #0a84ff;
	}

	.strong {
		font-weight: 600;
	}

	.scroll {
		display: grid;
		gap: 8px;
		padding: 8px 16px 16px;
		overflow: auto;
	}

	.caption {
		color: #aeaeb2;
		font-size: 12px;
		font-weight: 600;
		text-transform: uppercase;
	}

	label {
		display: grid;
		gap: 6px;
		margin-bottom: 8px;
	}

	input {
		border: 0;
		border-radius: 10px;
		padding: 10px 12px;
		background: #2e2e30;
	}

	.list {
		display: grid;
		border-radius: 10px;
		background: #2c2c2e;
		overflow: hidden;
	}

	.row {
		display: flex;
		justify-content: space-between;
		gap: 8px;
		border-bottom: 1px solid rgb(255 255 255 / 0.08);
		padding: 11px 12px;
		text-align: left;
	}

	.row.indented {
		padding-left: 40px;
	}

	.check {
		color: #0a84ff;
		font-weight: 700;
	}

	.error {
		margin: 0;
		color: #ff453a;
	}

	@media (min-width: 900px) {
		.scrim {
			place-items: center;
		}

		.sheet {
			border-radius: 16px;
		}
	}
</style>
