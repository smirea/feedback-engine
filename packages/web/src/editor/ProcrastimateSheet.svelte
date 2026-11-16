<svelte:options css="injected" />

<script lang="ts">
	import { Problem, taskTitle, type Fact, type FeedbackItem, type Session, type Toast } from '../core/index.ts';
	import type { Screen } from '../dom/capture.ts';
	import { annotatedImage } from '../dom/image.ts';
	import {
		cachedProjects,
		lastProject,
		loadProjects,
		namedProject,
		postTask,
		taskLink,
		type Place,
		type ProcrastimateConfig,
	} from '../dom/procrastimate.ts';
	import ProblemCard from './ProblemCard.svelte';
	import Sheet from './Sheet.svelte';

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
	// svelte-ignore state_referenced_locally
	let place = $state<Place>({
		projectId: config.project ? namedProject(projects, config.project)?.id : lastProject(),
	});
	let loading = $state(true);
	let loadProblem = $state<Problem>();
	let postProblem = $state<Problem>();
	/** What the post is doing, while it runs. */
	let step = $state<string>();
	const posting = $derived(step !== undefined);
	let status = $state<HTMLElement>();
	// svelte-ignore state_referenced_locally
	const environment: Fact[] = session.capture.environment.map(entry => ({ label: entry.name, value: entry.value }));

	$effect(() => {
		loadProjects(config)
			.then(loaded => {
				projects = loaded;
				if (config.project) {
					const named = namedProject(loaded, config.project);
					if (!named) throw new Error(`ProcrastiMate has no project named "${config.project}"`);
					place = { projectId: named.id };
				}
				const project = loaded.find(candidate => candidate.id === place.projectId);
				if (!project) place = {};
				else if (!project.sections.some(section => section.id === place.sectionId)) place = { projectId: project.id };
			})
			.catch(
				(error: unknown) =>
					(loadProblem = Problem.from(error).with([{ label: 'Step', value: 'Loading the projects' }], environment)),
			)
			.finally(() => (loading = false));
	});

	async function post() {
		step = 'Drawing the image';
		postProblem = undefined;
		const started = performance.now();
		const items = [...session.items];
		const project = projects.find(candidate => candidate.id === place.projectId);
		const section = project?.sections.find(candidate => candidate.id === place.sectionId);
		const report = session.compactJSON;
		const facts: Fact[] = [
			{
				label: 'Place',
				value: [project ? `${project.name} (${project.id})` : 'Inbox', section && `${section.name} (${section.id})`]
					.filter(Boolean)
					.join(' / '),
			},
			{ label: 'Report', value: `${new TextEncoder().encode(report).length} bytes` },
			{ label: 'Server', value: config.url },
		];
		try {
			const image = annotatedImage(screen, session.annotations);
			facts.push({ label: 'Image', value: `${image.width} × ${image.height} px` });
			const id = await postTask(config, name.trim(), place, image, report, text => (step = text));
			const destination = [project?.name ?? 'Inbox', section?.name].filter(Boolean).join(' / ');
			onposted(items, { text: `Added to ${destination} in ProcrastiMate`, link: taskLink(config, id) });
		} catch (error) {
			const elapsed = { label: 'Elapsed', value: `${((performance.now() - started) / 1000).toFixed(1)} s` };
			postProblem = Problem.from(error).with(
				[{ label: 'Step', value: step ?? 'Posting' }, elapsed],
				[...facts, ...environment],
			);
			step = undefined;
		}
	}

	// Above the project list, which can be longer than the sheet: an error under it goes unseen.
	$effect(() => {
		if (postProblem || step) status?.scrollIntoView({ block: 'nearest' });
	});
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

<Sheet label="Add to ProcrastiMate" onsubmit={() => void post()}>
	{#snippet header()}
		<button type="button" class="link" disabled={posting} onclick={onclose}>Cancel</button>
		<h2>Add to ProcrastiMate</h2>
		<button type="submit" class="link strong" disabled={posting || !name.trim()}>{posting ? 'Adding…' : 'Add'}</button>
	{/snippet}

	<div class="status" bind:this={status}>
		{#if step}<p class="step" role="status">{step}…</p>{/if}
		{#if postProblem}<ProblemCard problem={postProblem} />{/if}
		{#if loadProblem}<ProblemCard problem={loadProblem} />{/if}
	</div>
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
</Sheet>

<style>
	.strong {
		font-weight: 600;
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

	.status {
		display: grid;
		gap: 8px;
	}

	.status:empty {
		display: none;
	}

	.step {
		margin: 0;
		color: #aeaeb2;
	}
</style>
