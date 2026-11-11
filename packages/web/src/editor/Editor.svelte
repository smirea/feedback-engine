<svelte:options css="injected" />

<script lang="ts">
	import {
		hitTest,
		nearestComponent,
		nearestSource,
		paletteColor,
		Session,
		tag,
		title,
		type Frame,
	} from '../core/index.ts';
	import type { Screen } from '../dom/capture.ts';
	import {
		buildExport,
		canShare,
		copyExport,
		exportTitles,
		saveExport,
		shareExport,
		type Export,
		type ExportFormat,
	} from '../dom/share.ts';
	import type { Engine } from './engine.ts';
	import ItemsSheet from './ItemsSheet.svelte';
	import ProcrastimateSheet from './ProcrastimateSheet.svelte';

	let { engine, screen }: { engine: Engine; screen: Screen } = $props();

	// The host makes a new editor for each capture, so the first value is the only one.
	// svelte-ignore state_referenced_locally
	const { capture } = screen;
	const session = new Session(capture);
	const maxZoom = 4;

	/** `Session` is plain TypeScript, so every change to it goes through `act`, and everything drawn reads `view`. */
	let version = $state(0);
	const act = (change: () => void) => {
		change();
		version += 1;
	};
	const view = $derived.by(() => {
		void version;
		const path = session.path;
		const level = Math.min(session.level, path.length - 1);
		const target = session.target;
		const referencePath = session.referencePath;
		const referenceLevel = Math.min(session.referenceLevel, referencePath.length - 1);
		return {
			path,
			level,
			target,
			parent: path[level + 1],
			child: level > 0 ? path[level - 1] : undefined,
			source: nearestSource(capture, target.id),
			data: target.data ?? nearestComponent(capture, target.id)?.data,
			similar: session.similar,
			items: session.items.map((item, index) => ({
				...item,
				number: index + 1,
				color: paletteColor(session.colorIndex(item.target)),
			})),
			references: session.visibleReferences.map(reference => ({
				...reference,
				color: paletteColor(session.colorIndex(reference.target)),
			})),
			editing: session.editing,
			text: session.text,
			canSubmit: session.canSubmit,
			isReferencing: session.isReferencing,
			referenceTarget: session.referenceTarget,
			referenceParent: referencePath[referenceLevel + 1],
			referenceLevel,
			toast: session.toast,
		};
	});

	let dialog = $state<HTMLDialogElement>();
	let pane = $state<HTMLElement>();
	let field = $state<HTMLTextAreaElement>();
	let paneSize = $state({ width: 0, height: 0 });
	let zoom = $state(1);
	let hover = $state<number>();
	let showsList = $state(false);
	let showsShare = $state(false);
	let showsProcrastimate = $state(false);
	let confirmsClose = $state(false);
	let pending = $state<{ format: ExportFormat; ready: Export }>();
	let busy = $state(false);

	/** Fits the part that was on screen, and never goes below half the width, where targets get too small to tap. */
	const fit = $derived.by(() => {
		if (!paneSize.width) return 1;
		const widthFit = (paneSize.width - 24) / capture.size.width;
		return Math.min(
			1,
			Math.max(Math.min(widthFit, (paneSize.height - 16) / capture.visible.height), widthFit / 2, 0.05),
		);
	});
	const scale = $derived(fit * zoom);

	const box = (frame: Frame) =>
		`left:${frame.x * scale}px;top:${frame.y * scale}px;width:${Math.max(frame.width * scale, 4)}px;height:${Math.max(frame.height * scale, 4)}px`;

	$effect(() => {
		dialog?.showModal();
		// On a touch screen, focus would raise the keyboard over the screenshot before anything is picked.
		if (matchMedia('(pointer: fine)').matches) field?.focus();
		else dialog?.focus();
	});

	/**
	 * The screenshot's scale comes from the pane's first size and changes only with the window, so the picture does not
	 * jump as the panel grows with a selection or a longer draft.
	 */
	$effect(() => {
		if (!pane) return;
		const node = pane;
		const measure = () => {
			const style = getComputedStyle(node);
			paneSize = {
				width: node.clientWidth - Number.parseFloat(style.paddingLeft) - Number.parseFloat(style.paddingRight),
				height: node.clientHeight - Number.parseFloat(style.paddingTop) - Number.parseFloat(style.paddingBottom),
			};
		};
		measure();
		queueMicrotask(() => node.scrollTo({ top: capture.visible.y * fit }));
		addEventListener('resize', measure);
		return () => removeEventListener('resize', measure);
	});

	$effect(() => {
		const toast = view.toast;
		if (!toast) return;
		const timer = setTimeout(() => act(() => (session.toast = undefined)), toast.link ? 5000 : 3000);
		return () => clearTimeout(timer);
	});

	const pointAt = (event: MouseEvent) => {
		const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
		return { x: (event.clientX - rect.left) / scale, y: (event.clientY - rect.top) / scale };
	};

	function zoomTo(next: number, center: { x: number; y: number }) {
		if (!pane) return;
		const clamped = Math.min(maxZoom, Math.max(1, next));
		const rect = pane.getBoundingClientRect();
		const x = (pane.scrollLeft + center.x - rect.left) / zoom;
		const y = (pane.scrollTop + center.y - rect.top) / zoom;
		zoom = clamped;
		queueMicrotask(() =>
			pane?.scrollTo({ left: x * clamped - (center.x - rect.left), top: y * clamped - (center.y - rect.top) }),
		);
	}

	function wheel(event: WheelEvent) {
		if (!event.ctrlKey && !event.metaKey) return;
		event.preventDefault();
		zoomTo(zoom * Math.exp(-event.deltaY / 100), { x: event.clientX, y: event.clientY });
	}

	const touches = new Map<number, { x: number; y: number }>();
	let pinch: { distance: number; zoom: number } | undefined;
	const spread = () => {
		const [a, b] = [...touches.values()];
		return { distance: Math.hypot(a!.x - b!.x, a!.y - b!.y), center: { x: (a!.x + b!.x) / 2, y: (a!.y + b!.y) / 2 } };
	};
	function pointer(event: PointerEvent) {
		if (event.pointerType !== 'touch') return;
		if (event.type === 'pointerup' || event.type === 'pointercancel') {
			touches.delete(event.pointerId);
			pinch = undefined;
			return;
		}
		touches.set(event.pointerId, { x: event.clientX, y: event.clientY });
		if (touches.size !== 2) return;
		const { distance, center } = spread();
		pinch ??= { distance, zoom };
		zoomTo(pinch.zoom * (distance / pinch.distance), center);
	}

	function submit() {
		act(() => session.submit());
	}

	function keydown(event: KeyboardEvent) {
		if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
			event.preventDefault();
			if (view.isReferencing && view.referenceTarget) act(() => session.insertReference());
			else if (view.canSubmit) submit();
		}
	}

	function requestClose() {
		if (showsList || showsShare || showsProcrastimate || pending) {
			showsList = showsShare = showsProcrastimate = false;
			pending = undefined;
		} else if (session.isTyping || session.unshared.length) {
			confirmsClose = true;
		} else {
			engine.close();
		}
	}

	async function choose(format: ExportFormat) {
		showsShare = false;
		busy = true;
		try {
			const ready = await buildExport(screen, session.annotations, format);
			engine.lastExport = [{ name: ready.file.name, blob: ready.file }];
			pending = { format, ready };
		} finally {
			busy = false;
		}
	}

	async function finish(action: 'copy' | 'save' | 'share') {
		if (!pending) return;
		const { ready } = pending;
		const items = [...session.items];
		try {
			if (action === 'copy') await copyExport(ready);
			else if (action === 'save') saveExport(ready);
			else if (!(await shareExport(ready))) return;
		} catch (error) {
			act(() => (session.toast = { text: `Could not ${action}: ${(error as Error).message}` }));
			return;
		}
		pending = undefined;
		act(() => {
			session.markShared(items);
			session.toast = {
				text: action === 'copy' ? 'Copied' : action === 'save' ? `Saved ${ready.file.name}` : 'Shared',
			};
		});
	}

	const count = (items: number) => (items === 1 ? '1 item' : `${items} items`);
</script>

<dialog
	bind:this={dialog}
	class="editor"
	aria-label="Feedback"
	oncancel={event => {
		event.preventDefault();
		requestClose();
	}}
>
	<header>
		<button type="button" class="round" aria-label="Close" onclick={requestClose}>
			<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg>
		</button>
		<h1>Feedback</h1>
		<button
			type="button"
			class="round"
			aria-label="Feedback list, {count(view.items.length)}"
			onclick={() => (showsList = true)}
		>
			<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 6h11M9 12h11M9 18h11M4 6h.01M4 12h.01M4 18h.01" /></svg>
			{#if view.items.length}<span class="count" aria-hidden="true">{view.items.length}</span>{/if}
		</button>
		<div class="menu">
			<button
				type="button"
				class="round"
				aria-label="Share"
				aria-haspopup="menu"
				aria-expanded={showsShare}
				disabled={!view.items.length || busy}
				onclick={() => (showsShare = !showsShare)}
			>
				<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 15V4M8 8l4-4 4 4M5 12v7h14v-7" /></svg>
			</button>
			{#if showsShare}
				<div class="popup" role="menu">
					{#each Object.entries(exportTitles) as [format, name] (format)}
						<button type="button" role="menuitem" onclick={() => void choose(format as ExportFormat)}>{name}</button>
					{/each}
					{#if engine.options.procrastimate}
						<button
							type="button"
							role="menuitem"
							onclick={() => {
								showsShare = false;
								showsProcrastimate = true;
							}}>ProcrastiMate</button
						>
					{/if}
				</div>
			{/if}
		</div>
	</header>

	<div class="body">
		<div
			class="pane"
			role="group"
			aria-label="Screenshot"
			bind:this={pane}
			onwheel={wheel}
			onpointerdown={pointer}
			onpointermove={pointer}
			onpointerup={pointer}
			onpointercancel={pointer}
		>
			<!-- A screenshot has no keyboard equivalent for pointing at a pixel. The chain buttons reach every node from the keyboard. -->
			<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
			<div
				class="canvas"
				role="img"
				aria-label="Screenshot. Click a component to give it feedback."
				style="width:{capture.size.width * scale}px;height:{capture.size.height * scale}px"
				onclick={event => act(() => session.pick(pointAt(event)))}
				onmousemove={event => (hover = hitTest(capture, pointAt(event)))}
				onmouseleave={() => (hover = undefined)}
				{@attach node => {
					node.prepend(screen.image);
				}}
			>
				{#each view.similar as id (id)}
					<span class="box similar" style={box(capture.nodes[id]!.frame)}></span>
				{/each}
				{#each view.items as item (item.id)}
					<span class="box item" style="{box(capture.nodes[item.target]!.frame)};--color:{item.color}">
						<span class="number">{item.number}</span>
					</span>
				{/each}
				{#each view.references as reference (reference.number)}
					<span class="box item" style="{box(capture.nodes[reference.target]!.frame)};--color:{reference.color}">
						<span class="tag">{tag(reference)}</span>
					</span>
				{/each}
				{#if hover !== undefined && hover !== view.target.id && capture.nodes[hover]!.kind !== 'screen'}
					<span class="box hover" style={box(capture.nodes[hover]!.frame)}></span>
				{/if}
				{#if view.target.kind !== 'screen'}
					<span class="box target" style={box(view.target.frame)}></span>
				{/if}
				{#if view.referenceTarget}
					<span class="box reference" style={box(view.referenceTarget.frame)}></span>
				{/if}
			</div>
		</div>

		<section class="panel" aria-label="Selection">
			{#if view.path.length > 1}
				<div class="chain">
					<span class="side">
						{#if view.parent}
							<button
								type="button"
								class="neighbor"
								aria-label="Select parent, {title(view.parent)}"
								onclick={() => act(() => session.step(view.level + 1))}
							>
								‹ {view.parent.name}
							</button>
						{/if}
					</span>
					<strong class="selected">{title(view.target)}</strong>
					<span class="side end">
						{#if view.child}
							<button
								type="button"
								class="neighbor"
								aria-label="Select child, {title(view.child)}"
								onclick={() => act(() => session.step(view.level - 1))}
							>
								{view.child.name} ›
							</button>
						{/if}
					</span>
				</div>
			{:else}
				<p class="hint">Click the screenshot to pick a component.</p>
			{/if}
			<div class="meta">
				<span class="source">{view.source ?? ''}</span>
				{#if view.similar.length}<span class="similar-count">{view.similar.length} similar</span>{/if}
			</div>
			<pre class="data">{view.data ?? ' '}</pre>
			{#if view.isReferencing}
				<div class="picker">
					{#if view.referenceTarget}
						<button
							type="button"
							class="round small"
							aria-label="Select parent"
							disabled={!view.referenceParent}
							onclick={() => act(() => session.stepReference(view.referenceLevel + 1))}
						>
							<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 15l6-6 6 6" /></svg>
						</button>
						<button
							type="button"
							class="round small"
							aria-label="Select child"
							disabled={view.referenceLevel === 0}
							onclick={() => act(() => session.stepReference(view.referenceLevel - 1))}
						>
							<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 9l6 6 6-6" /></svg>
						</button>
						<strong class="picked">{title(view.referenceTarget)}</strong>
						<button type="button" class="insert" onclick={() => act(() => session.insertReference())}>Insert</button>
					{:else}
						<span class="picked">@ Click an element to reference it</span>
					{/if}
				</div>
			{/if}
			<div class="compose">
				{#if view.editing}
					{@const item = view.items.find(candidate => candidate.id === view.editing!.id)!}
					<span class="number static" style="--color:{item.color}" aria-label="Editing item {item.number}"
						>{item.number}</span
					>
				{/if}
				<textarea
					bind:this={field}
					rows="1"
					aria-label="Feedback text"
					placeholder="Feedback on {view.target.name}…"
					value={view.text}
					oninput={event => act(() => (session.text = event.currentTarget.value))}
					onkeydown={keydown}></textarea>
				<button
					type="button"
					class="send"
					aria-label={view.editing ? 'Save feedback' : 'Add feedback'}
					disabled={!view.canSubmit}
					onclick={submit}
				>
					<svg viewBox="0 0 24 24" aria-hidden="true">
						{#if view.editing}<path d="M6 12l4 4 8-8" />{:else}<path d="M12 18V7M7 11l5-5 5 5" />{/if}
					</svg>
				</button>
			</div>
		</section>
	</div>

	{#if view.toast}
		<div class="toast" role="status">
			<button
				type="button"
				onclick={() => {
					if (view.toast?.link) open(view.toast.link, '_blank', 'noopener');
					act(() => (session.toast = undefined));
				}}
			>
				✓ {view.toast.text}{view.toast.link ? ' ↗' : ''}
			</button>
		</div>
	{/if}

	{#if showsList}
		<ItemsSheet
			{session}
			{version}
			onclose={() => (showsList = false)}
			onselect={id => {
				act(() => session.select(id));
				showsList = false;
			}}
			onremove={id => act(() => session.remove(id))}
		/>
	{/if}

	{#if showsProcrastimate && engine.options.procrastimate}
		<ProcrastimateSheet
			{screen}
			{session}
			config={engine.options.procrastimate}
			onclose={() => (showsProcrastimate = false)}
			onposted={(items, toast) => {
				showsProcrastimate = false;
				act(() => {
					session.markShared(items);
					session.toast = toast;
				});
			}}
		/>
	{/if}

	{#if pending}
		<div
			class="scrim"
			role="presentation"
			onclick={event => event.target === event.currentTarget && (pending = undefined)}
		>
			<div class="sheet actions" role="dialog" tabindex="-1" aria-label="Share {exportTitles[pending.format]}">
				<h2>{pending.ready.file.name}</h2>
				<button type="button" onclick={() => void finish('copy')}>Copy Feedback</button>
				<button type="button" onclick={() => void finish('save')}>Save File</button>
				{#if canShare(pending.ready)}
					<button type="button" onclick={() => void finish('share')}>Share…</button>
				{/if}
				<button type="button" class="quiet" onclick={() => (pending = undefined)}>Cancel</button>
			</div>
		</div>
	{/if}

	{#if confirmsClose}
		<div class="scrim" role="presentation">
			<div class="sheet actions" role="alertdialog" tabindex="-1" aria-label="Discard feedback?">
				<h2>Discard feedback?</h2>
				<p>
					{session.unshared.length
						? `Closing discards ${count(session.unshared.length)} you haven't shared.`
						: "Closing discards the feedback you're typing."}
				</p>
				<button type="button" class="danger" onclick={() => engine.close()}>Discard</button>
				<button type="button" class="quiet" onclick={() => (confirmsClose = false)}>Keep Editing</button>
			</div>
		</div>
	{/if}
</dialog>

<style>
	.editor {
		position: fixed;
		inset: 0;
		display: flex;
		flex-direction: column;
		width: 100vw;
		height: 100dvh;
		max-width: none;
		max-height: none;
		margin: 0;
		border: 0;
		padding: 0;
		background: #141414;
		color: white;
		color-scheme: dark;
		font:
			15px/1.35 system-ui,
			-apple-system,
			'Segoe UI',
			sans-serif;
		overflow: hidden;
	}

	.editor::backdrop {
		background: #141414;
	}

	button,
	textarea {
		font: inherit;
		color: inherit;
	}

	button {
		cursor: pointer;
	}

	button:disabled {
		cursor: default;
		opacity: 0.4;
	}

	header {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 8px 16px;
	}

	h1 {
		flex: 1;
		margin: 0;
		font-size: 17px;
		font-weight: 600;
		text-align: center;
	}

	.round {
		position: relative;
		display: grid;
		place-items: center;
		width: 36px;
		height: 36px;
		border: 0;
		border-radius: 50%;
		background: #2c2c2e;
	}

	.round.small {
		width: 30px;
		height: 30px;
	}

	svg {
		width: 18px;
		height: 18px;
		fill: none;
		stroke: currentColor;
		stroke-width: 2.2;
		stroke-linecap: round;
		stroke-linejoin: round;
	}

	.count {
		position: absolute;
		top: -4px;
		right: -4px;
		min-width: 18px;
		border-radius: 9px;
		padding: 0 4px;
		background: #ff3b30;
		font-size: 11px;
		font-weight: 700;
		line-height: 18px;
	}

	.menu {
		position: relative;
	}

	.popup {
		position: absolute;
		top: 42px;
		right: 0;
		z-index: 3;
		display: grid;
		min-width: 220px;
		border-radius: 12px;
		background: #2c2c2e;
		box-shadow: 0 12px 40px rgb(0 0 0 / 0.5);
		overflow: hidden;
	}

	.popup button {
		border: 0;
		border-bottom: 1px solid rgb(255 255 255 / 0.08);
		padding: 12px 16px;
		background: none;
		text-align: left;
	}

	.popup button:hover {
		background: rgb(255 255 255 / 0.08);
	}

	.body {
		display: flex;
		flex: 1;
		flex-direction: column;
		min-height: 0;
	}

	.pane {
		flex: 1;
		min-height: 0;
		padding: 8px 12px;
		overflow: auto;
		overscroll-behavior: contain;
		touch-action: pan-x pan-y;
	}

	.canvas {
		position: relative;
		margin: 0 auto;
		border-radius: 10px;
		overflow: hidden;
		cursor: crosshair;
	}

	.canvas :global(canvas) {
		display: block;
		width: 100%;
		height: 100%;
	}

	.box {
		position: absolute;
		box-sizing: border-box;
		border-radius: 3px;
		pointer-events: none;
	}

	.box.similar {
		border: 1px dashed rgb(255 214 10 / 0.5);
		background: rgb(255 214 10 / 0.08);
	}

	.box.item {
		border: 1.5px dashed var(--color);
	}

	.box.target {
		border: 2px dashed #ffd60a;
	}

	.box.hover {
		border: 1px solid rgb(255 255 255 / 0.7);
		background: rgb(255 255 255 / 0.06);
	}

	.box.reference {
		border: 2px dashed #32ade6;
		background: rgb(50 173 230 / 0.12);
	}

	.number,
	.tag {
		position: absolute;
		top: -7px;
		display: grid;
		place-items: center;
		min-width: 16px;
		height: 16px;
		padding: 0 3px;
		box-sizing: border-box;
		background: var(--color);
		color: white;
		font-size: 11px;
		font-weight: 700;
		line-height: 1;
	}

	.number {
		left: -7px;
		border-radius: 8px;
	}

	.tag {
		right: -7px;
		border-radius: 3px;
	}

	.number.static {
		position: static;
		width: 22px;
		height: 22px;
		border-radius: 11px;
		margin-bottom: 8px;
		font-size: 12px;
	}

	.panel {
		display: grid;
		gap: 10px;
		padding: 16px;
		padding-bottom: max(16px, env(safe-area-inset-bottom));
		background: #1f1f1f;
	}

	.chain {
		display: flex;
		align-items: center;
		gap: 8px;
	}

	.side {
		display: flex;
		flex: 1;
		min-width: 0;
	}

	.side.end {
		justify-content: flex-end;
	}

	.neighbor {
		max-width: 100%;
		border: 0;
		border-radius: 999px;
		padding: 6px 10px;
		background: #333336;
		color: #aeaeb2;
		font-size: 14px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.selected {
		color: #ffd60a;
		font-size: 16px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.hint {
		margin: 0;
		color: #aeaeb2;
	}

	.meta {
		display: flex;
		justify-content: space-between;
		gap: 8px;
		min-height: 16px;
		color: #aeaeb2;
		font:
			12px ui-monospace,
			'SF Mono',
			Menlo,
			monospace;
	}

	.source {
		direction: rtl;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.similar-count {
		flex: none;
		color: rgb(255 214 10 / 0.7);
	}

	.data {
		height: 3.9em;
		margin: 0;
		color: #aeaeb2;
		font:
			11px/1.3 ui-monospace,
			'SF Mono',
			Menlo,
			monospace;
		overflow: hidden;
		white-space: pre-wrap;
	}

	.picker {
		display: flex;
		align-items: center;
		gap: 8px;
		min-height: 34px;
	}

	.picked {
		flex: 1;
		color: #32ade6;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.insert {
		border: 0;
		border-radius: 999px;
		padding: 6px 14px;
		background: #32ade6;
		font-weight: 600;
	}

	.compose {
		display: flex;
		align-items: flex-end;
		gap: 8px;
	}

	textarea {
		flex: 1;
		min-height: 38px;
		max-height: 6.5em;
		border: 0;
		border-radius: 18px;
		padding: 8px 12px;
		box-sizing: border-box;
		background: #2e2e30;
		field-sizing: content;
		resize: none;
	}

	textarea:focus-visible,
	button:focus-visible {
		outline: 2px solid #0a84ff;
		outline-offset: 1px;
	}

	.send {
		display: grid;
		place-items: center;
		width: 36px;
		height: 36px;
		border: 0;
		border-radius: 50%;
		background: #0a84ff;
	}

	.toast {
		position: absolute;
		top: 60px;
		left: 50%;
		z-index: 4;
		translate: -50% 0;
	}

	.toast button {
		border: 0;
		border-radius: 999px;
		padding: 10px 16px;
		background: rgb(52 199 89 / 0.92);
		font-weight: 600;
	}

	.scrim {
		position: absolute;
		inset: 0;
		z-index: 5;
		display: grid;
		place-items: end center;
		background: rgb(0 0 0 / 0.5);
	}

	.sheet {
		width: min(100%, 420px);
		border-radius: 16px 16px 0 0;
		padding: 16px;
		padding-bottom: max(16px, env(safe-area-inset-bottom));
		box-sizing: border-box;
		background: #1f1f1f;
	}

	.actions {
		display: grid;
		gap: 8px;
	}

	.actions h2 {
		margin: 0 0 4px;
		font-size: 16px;
		text-align: center;
	}

	.actions p {
		margin: 0 0 4px;
		color: #aeaeb2;
		text-align: center;
	}

	.actions button {
		border: 0;
		border-radius: 12px;
		padding: 12px;
		background: #2c2c2e;
		font-weight: 600;
	}

	.actions .danger {
		color: #ff453a;
	}

	.actions .quiet {
		background: none;
		color: #aeaeb2;
	}

	@media (min-width: 900px) {
		.body {
			flex-direction: row;
		}

		.panel {
			align-content: start;
			width: 380px;
			box-sizing: border-box;
			border-left: 1px solid rgb(255 255 255 / 0.08);
		}

		.data {
			height: auto;
			max-height: 40vh;
			overflow: auto;
		}

		.scrim {
			place-items: center;
		}

		.sheet {
			border-radius: 16px;
		}
	}
</style>
