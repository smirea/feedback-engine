import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PNG } from 'pngjs';
import {
	canvas,
	captureImage,
	difference,
	editor,
	exportReport,
	field,
	lastExport,
	appNames,
	modes,
	open,
	outline,
	present,
	procrastimate,
	root,
	startServers,
	stopServers,
	tap,
	type EngineName,
} from './app.ts';

beforeAll(startServers, 120_000);
afterAll(stopServers);

const engineNames: EngineName[] = ['chromium', 'webkit'];
const selected = (page: Parameters<typeof editor>[0]) => page.locator('.selected').innerText();

/** What differs between the two example apps: where each component is declared, and React's `App` around every screen. */
const expected = {
	svelte: {
		lists: [
			'Screen',
			'  ListsScreen  src/routes/+page.svelte:23',
			'    Header "Lists"',
			'    Button "New List"',
			'    SummaryCard  src/lib/SummaryCard.svelte:15',
			'      Stat  src/lib/Stat.svelte:6',
			'        Text "21"',
			'        Text "Open"',
			'      Stat  src/lib/Stat.svelte:6',
			'        Text "1"',
			'        Text "Due today"',
			'      Stat  src/lib/Stat.svelte:6',
			'        Text "3"',
			'        Text "Lists"',
			'    Header "My Lists"',
			'    Link "Groceries 17"',
			'      ListRow  src/lib/ListRow.svelte:10',
			'    Link "Work 3"',
			'      ListRow  src/lib/ListRow.svelte:10',
			'    Link "Home 1"',
			'      ListRow  src/lib/ListRow.svelte:10',
			'  TabBar  src/lib/TabBar.svelte:13',
			'    Link "Lists"',
			'    Link "Settings"',
		],
		newListButton: 'src/routes/+page.svelte:26',
		listsHeader: 'src/routes/+page.svelte:25',
		listRow: 'src/lib/ListRow.svelte:10',
		detailDialog: '    TodoDetailDialog  src/lib/TodoDetailDialog.svelte:24',
		sortMenu: '    SortMenu  src/routes/lists/[id]/+page.svelte:84',
		tapsOptions: [] as string[],
	},
	react: {
		lists: [
			'Screen',
			'  App  src/App.tsx:10',
			'    ListsScreen  src/screens/ListsScreen.tsx:8',
			'      Header "Lists"',
			'      Button "New List"',
			'      SummaryCard  src/components/SummaryCard.tsx:4',
			'        Stat  src/components/Stat.tsx:1',
			'          Text "21"',
			'          Text "Open"',
			'        Stat  src/components/Stat.tsx:1',
			'          Text "1"',
			'          Text "Due today"',
			'        Stat  src/components/Stat.tsx:1',
			'          Text "3"',
			'          Text "Lists"',
			'      Header "My Lists"',
			'      Link "Groceries 17"',
			'        ListRow  src/components/ListRow.tsx:4',
			'      Link "Work 3"',
			'        ListRow  src/components/ListRow.tsx:4',
			'      Link "Home 1"',
			'        ListRow  src/components/ListRow.tsx:4',
			'    TabBar  src/components/TabBar.tsx:8',
			'      Link "Lists"',
			'      Link "Settings"',
		],
		newListButton: 'src/screens/ListsScreen.tsx:30',
		listsHeader: 'src/screens/ListsScreen.tsx:29',
		listRow: 'src/components/ListRow.tsx:4',
		detailDialog: '    TodoDetailDialog  src/components/TodoDetailDialog.tsx:7',
		sortMenu: '    SortMenu  src/screens/ListDetailScreen.tsx:116',
		tapsOptions: ['--wrapper', 'App'],
	},
};

for (const app of appNames) {
	describe(`the ${app} example`, () => {
		for (const mode of modes) {
			for (const engine of engineNames) {
				describe(`${mode} build in ${engine}`, () => {
					test('the Lists screen exports its components, elements, and context', async () => {
						const { page, context, errors } = await open(app, engine, mode, '/');
						await present(page);
						expect(await page.getByText('Click the screenshot to pick a component.').count()).toBe(1);
						const report = await exportReport(page);

						expect(outline(report)).toEqual(expected[app].lists);
						const node = (title: string) =>
							report.nodes.find(candidate => `${candidate.name} "${candidate.label}"` === title)!;
						// Every element has its own location in development builds only.
						expect(node('Button "New List"').source).toBe(mode === 'dev' ? expected[app].newListButton : undefined);
						expect(report.nodes.find(candidate => candidate.name === 'ListRow')!.data).toBe(
							'name: Groceries\nremaining: 17\ntotal: 19',
						);
						expect(report.nodes.filter(candidate => candidate.name === 'Stat').map(stat => stat.data)).toEqual([
							'value: 21\nlabel: Open',
							'value: 1\nlabel: Due today',
							'value: 3\nlabel: Lists',
						]);

						expect(report.app).toBe('Todo');
						expect(report.environment.map(entry => entry.name)).toEqual([
							'App',
							'Location',
							'Version',
							'Device',
							'Display',
							'Captured',
							'Locale',
						]);
						expect(report.environment.slice(1, 3)).toEqual([
							{ name: 'Location', value: '/' },
							{ name: 'Version', value: '1.0' },
						]);
						expect(report.context.map(entry => entry.name)).toEqual(['TodoStore']);
						// A production build minifies the class's name.
						expect(report.context[0]!.value).toMatch(
							mode === 'dev'
								? /^TodoStore\(lists: \[\{id: "groceries", name: "Groceries", /
								: /^\w+\(lists: \[\{id: "groceries", name: "Groceries", /,
						);
						expect(report.items).toEqual([{ number: 1, text: 'Looks off', target: 0, title: 'Screen', path: [0] }]);

						const file = join(mkdtempSync(join(tmpdir(), 'feedback-')), 'feedback.json');
						writeFileSync(file, JSON.stringify(report));
						const taps = Bun.spawnSync([
							'python3',
							join(root, 'skills/feedback-accessibility/scripts/taps.py'),
							file,
							...expected[app].tapsOptions,
						]);
						// The screen's own component is a root in both apps, so both list the loose elements directly under it.
						expect(taps.stdout.toString()).toStartWith('Fall-through: ');
						expect(taps.stdout.toString()).toContain('Header "Lists"');
						expect(taps.exitCode).toBe(0);
						expect(errors).toEqual([]);
						await context.close();
					});

					test('a scrolled page is captured at full length, with fixed content where it was on screen', async () => {
						const { page, context, errors } = await open(app, engine, mode, '/timeline');
						await page.evaluate(() => scrollTo(0, 1500));
						const window = await page.screenshot();
						await present(page);
						expect(await page.evaluate(() => scrollY)).toBe(1500);

						// Text is drawn a little differently in a canvas than on screen, more so on Linux than on macOS.
						expect(difference(await captureImage(page), window, 1500 * 2)).toBeLessThan(0.01);
						const report = await exportReport(page);
						expect(report.size.width).toBe(390);
						expect(report.size.height).toBeGreaterThan(5000);
						expect(report.visible).toEqual({ x: 0, y: 1500, width: 390, height: 700 });

						const tabs = report.nodes.find(candidate => candidate.name === 'TabBar')!;
						expect(tabs.frame.y + tabs.frame.height).toBe(2200);
						const days = report.nodes.filter(candidate => candidate.name === 'DayHeader');
						expect(days.map(day => day.data)).toEqual(
							['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'].map(
								day => `day: ${day}\ncount: 9`,
							),
						);
						expect(days.every((day, index) => index === 0 || day.frame.y > days[index - 1]!.frame.y + 600)).toBe(true);
						expect(report.nodes.filter(candidate => candidate.name === 'TimelineRow').length).toBe(63);
						expect(errors).toEqual([]);
						await context.close();
					});

					test('a modal dialog is a layer over the page, and what it covers is left out', async () => {
						const { page, context, errors } = await open(app, engine, mode, '/lists/groceries');
						await page.evaluate(() => scrollTo(0, 300));
						await page.getByRole('button', { name: 'Bananas' }).click();
						await page.getByRole('heading', { name: 'Details' }).waitFor();
						await page.locator(':focus').blur();
						const window = await page.screenshot();
						await present(page);

						expect(difference(await captureImage(page), window, 300 * 2)).toBeLessThan(0.02);
						const report = await exportReport(page);
						const due = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
						expect(outline(report, 1)).toEqual([
							'  Dialog',
							expected[app].detailDialog,
							'      Header "Details"',
							'      Text field "Title, Bananas"',
							'      Text field "Notes, Not too ripe"',
							'      Text "Due date"',
							'        Checkbox "Due date, on"',
							`      Text "Due"`,
							`        Text field "Due, ${due}"`,
							'      Text "Priority"',
							'        Combo box "Priority, none"',
							'      Button "Delete Todo"',
							'      Button "Cancel"',
							'      Button "Save"',
						]);
						const dialog = report.nodes.find(candidate => candidate.kind === 'layer')!.frame;
						const inside = (frame: typeof dialog) =>
							frame.x >= dialog.x &&
							frame.y >= dialog.y &&
							frame.x + frame.width <= dialog.x + dialog.width &&
							frame.y + frame.height <= dialog.y + dialog.height;
						expect(
							report.nodes.filter(
								candidate => candidate.layer === 0 && candidate.kind !== 'screen' && inside(candidate.frame),
							),
						).toEqual([]);
						expect(report.nodes.some(candidate => candidate.label === 'Mark All Done')).toBe(true);

						await tap(page, dialog.x + 40, dialog.y + 30);
						expect(await selected(page)).toBe('Header "Details"');
						expect(errors).toEqual([]);
						await context.close();
					});
				});
			}
		}

		for (const [name, viewport] of [
			['desktop', { width: 1280, height: 800 }],
			['phone', { width: 390, height: 700 }],
		] as const) {
			for (const engine of engineNames) {
				test(`giving feedback at ${name} width in ${engine}`, async () => {
					const { page, context, errors } = await open(app, engine, 'dev', '/', viewport);
					const report = async () => JSON.parse((await lastExport(page))[0]!.bytes.toString());

					// Alt+Meta+click opens the editor on the row under the pointer, and the link under it does not take the click.
					await page.getByRole('link', { name: /^Groceries/ }).click({ modifiers: ['Alt', 'Meta'] });
					await editor(page).waitFor();
					expect(new URL(page.url()).pathname).toBe('/');
					expect(await selected(page)).toBe('ListRow');
					expect(await page.getByRole('button', { name: 'Share' }).isDisabled()).toBe(true);
					// The editor is a modal dialog in the top layer, so the page under it takes no clicks and assistive technology skips it.
					const covered = () =>
						page.evaluate(
							() => document.elementFromPoint(innerWidth / 2, 40)?.hasAttribute('data-feedback-engine') ?? false,
						);
					expect(await covered()).toBe(true);

					const left = (viewport.width - Math.min(viewport.width, 640)) / 2;
					const groceries = { x: left + 100, y: 270 };
					await tap(page, groceries.x, groceries.y);
					expect(await selected(page)).toBe('ListRow');
					expect(await page.locator('.source').innerText()).toBe(expected[app].listRow);
					expect(await page.locator('.similar-count').innerText()).toBe('2 similar');
					expect(await page.locator('.data').innerText()).toBe('name: Groceries\nremaining: 17\ntotal: 19');
					expect(await page.locator('.box.similar').count()).toBe(2);

					await page.getByRole('button', { name: /^Select parent/ }).click();
					expect(await selected(page)).toBe('Link "Groceries 17"');
					await page.getByRole('button', { name: /^Select child/ }).click();
					expect(await selected(page)).toBe('ListRow');

					await field(page).fill('Row is too tall');
					await page.getByRole('button', { name: 'Add feedback' }).click();
					expect(await page.locator('.box.item .number').allInnerTexts()).toEqual(['1']);

					await tap(page, left + 40, 60);
					expect(await selected(page)).toBe('Header "Lists"');
					await field(page).fill('Smaller, like @');
					expect(await page.getByText('Click an element to reference it').count()).toBe(1);
					await tap(page, groceries.x, groceries.y);
					expect(await selected(page)).toBe('Header "Lists"');
					await page.getByRole('button', { name: 'Insert' }).click();
					expect(await field(page).inputValue()).toBe('Smaller, like @1_ListRow ');
					await field(page).press('Enter');
					expect(await page.locator('.box.item .tag').allInnerTexts()).toEqual(['@1']);

					await tap(page, groceries.x, groceries.y);
					expect(await field(page).inputValue()).toBe('Row is too tall');
					await field(page).fill('Row is too tall on phones');
					await page.getByRole('button', { name: 'Save feedback' }).click();

					await page.getByRole('button', { name: 'Feedback list, 2 items' }).click();
					const list = page.getByRole('dialog', { name: 'Feedback list' });
					expect(await list.locator('li strong').allInnerTexts()).toEqual(['ListRow', 'Header "Lists"']);
					expect(await list.locator('.token').allInnerTexts()).toEqual(['@1_ListRow']);
					expect(await list.locator('summary').allInnerTexts()).toEqual([
						'App',
						'Location',
						'Version',
						'Device',
						'Display',
						'Captured',
						'Locale',
						'TodoStore',
					]);
					await list.getByRole('button', { name: 'Done' }).click();

					await page.getByRole('button', { name: 'Close' }).click();
					const confirm = page.getByRole('alertdialog', { name: 'Discard feedback?' });
					expect(await confirm.locator('p').innerText()).toBe("Closing discards 2 items you haven't shared.");
					await confirm.getByRole('button', { name: 'Keep Editing' }).click();

					await page.getByRole('button', { name: 'Share' }).click();
					await page.getByRole('menuitem', { name: 'Image and JSON (ZIP)' }).click();
					await page.getByRole('dialog', { name: 'Share Image and JSON (ZIP)' }).waitFor();
					const [archive] = await lastExport(page);
					expect(archive!.name).toBe('feedback.zip');
					const folder = mkdtempSync(join(tmpdir(), 'feedback-'));
					writeFileSync(join(folder, 'feedback.zip'), archive!.bytes);
					expect(Bun.spawnSync(['unzip', '-o', 'feedback.zip'], { cwd: folder }).exitCode).toBe(0);
					const zipped = JSON.parse(await Bun.file(join(folder, 'feedback/feedback.json')).text());
					expect(
						zipped.items.map((item: { text: string; title: string; code: string }) => [
							item.title,
							item.text,
							item.code,
						]),
					).toEqual([
						['ListRow', 'Row is too tall on phones', expected[app].listRow],
						['Header "Lists"', 'Smaller, like @1_ListRow', expected[app].listsHeader],
					]);
					expect(
						zipped.references.map((reference: { token: string; title: string }) => [reference.token, reference.title]),
					).toEqual([['@1_ListRow', 'ListRow']]);
					const image = PNG.sync.read(Buffer.from(await Bun.file(join(folder, 'feedback/feedback.png')).arrayBuffer()));
					// Two card columns, two gutters, and two margins around the capture, at the capture's 2x scale.
					expect(image.width).toBe((24 + 280 + 36 + viewport.width + 36 + 280 + 24) * 2);
					expect(image.height).toBe((24 + zipped.size.height + 24) * 2);

					if (engine === 'chromium') {
						await page.getByRole('button', { name: 'Copy Feedback' }).click();
						expect(await page.locator('.toast').innerText()).toBe('✓ Copied');
						const clipboard = await page.evaluate(async () =>
							(await navigator.clipboard.read()).map(item => [...item.types].toSorted()),
						);
						expect(clipboard).toEqual([['image/png', 'text/plain']]);
						expect(JSON.parse(await page.evaluate(() => navigator.clipboard.readText())).items.length).toBe(2);
					} else {
						const download = page.waitForEvent('download');
						await page.getByRole('button', { name: 'Save File' }).click();
						expect((await download).suggestedFilename()).toBe('feedback.zip');
					}

					await page.getByRole('button', { name: 'Feedback list, 2 items' }).click();
					await list.getByRole('button', { name: 'Remove item 1' }).click();
					await list.getByRole('button', { name: 'Done' }).click();
					await page.getByRole('button', { name: 'Share' }).click();
					await page.getByRole('menuitem', { name: 'JSON', exact: true }).click();
					await page.getByRole('dialog', { name: 'Share JSON' }).waitFor();
					expect((await report()).items.map((item: { text: string }) => item.text)).toEqual([
						'Smaller, like @1_ListRow',
					]);
					await page.getByRole('dialog', { name: 'Share JSON' }).getByRole('button', { name: 'Cancel' }).click();

					await page.getByRole('button', { name: 'Close' }).click();
					await editor(page).waitFor({ state: 'detached' });
					expect(await covered()).toBe(false);
					expect(errors).toEqual([]);
					await context.close();
				});
			}
		}

		test('the pill leaves by itself after five seconds, and showing it again restarts the timer', async () => {
			const { page, context } = await open(app, 'chromium', 'dev', '/');
			const pill = page.getByRole('button', { name: 'Add Feedback' });
			await page.evaluate(() => globalThis.__feedbackEngine!.showPill());
			await pill.waitFor();
			await page.waitForTimeout(3000);
			await page.evaluate(() => globalThis.__feedbackEngine!.showPill());
			await page.waitForTimeout(3000);
			expect(await pill.count()).toBe(1);
			await page.waitForTimeout(2500);
			expect(await pill.count()).toBe(0);
			await context.close();
		}, 30_000);

		for (const engine of engineNames) {
			test(`Alt+Meta+click opens the editor on what was clicked, and the app never gets the click, in ${engine}`, async () => {
				const { page, context, errors } = await open(app, engine, 'dev', '/lists/groceries');
				const close = async () => {
					await page.getByRole('button', { name: 'Close' }).click();
					await editor(page).waitFor({ state: 'detached' });
				};

				await page.getByRole('button', { name: 'Mark All Done' }).click({ modifiers: ['Alt', 'Meta'] });
				await editor(page).waitFor();
				expect(await selected(page)).toBe('Button "Mark All Done"');
				await close();
				expect(await page.getByText('2 of 19 done').count()).toBe(1);

				// A disabled button takes no click of its own, and a person still points at it.
				await page.getByRole('button', { name: 'Add', exact: true }).click({ modifiers: ['Alt', 'Meta'], force: true });
				await editor(page).waitFor();
				expect(await selected(page)).toBe('Button "Add"');
				await close();

				// Any other chord belongs to the app.
				await page.getByRole('button', { name: 'Mark All Done' }).click({ modifiers: ['Alt'] });
				expect(await page.getByText('19 of 19 done').count()).toBe(1);
				expect(await editor(page).count()).toBe(0);
				expect(errors).toEqual([]);
				await context.close();
			});
		}

		test("a countdown from the app's own menu captures the screen the user goes to", async () => {
			const { page, context, errors } = await open(app, 'chromium', 'dev', '/settings');
			await page.getByRole('button', { name: 'Send Feedback' }).click();
			await page.getByRole('button', { name: 'Feedback in 5' }).waitFor();
			await page.getByRole('link', { name: 'Lists', exact: true }).click();
			await page.getByRole('heading', { name: 'Lists', level: 1 }).waitFor();
			await page.getByRole('button', { name: 'Feedback in 3' }).waitFor();
			expect(await editor(page).count()).toBe(0);
			await editor(page).waitFor({ timeout: 8000 });
			const report = await exportReport(page);
			expect(report.environment[1]).toEqual({ name: 'Location', value: '/' });
			expect(report.nodes.some(node => node.name === 'ListsScreen')).toBe(true);
			await page.getByRole('button', { name: 'Close' }).click();
			await page.getByRole('alertdialog').getByRole('button', { name: 'Discard' }).click();
			await editor(page).waitFor({ state: 'detached' });

			// Pressing the pill captures at once.
			await page.evaluate(() => globalThis.__feedbackEngine!.countdown());
			await page.getByRole('button', { name: 'Feedback in 5' }).click();
			await editor(page).waitFor({ timeout: 1500 });
			expect(errors).toEqual([]);
			await context.close();
		}, 30_000);

		test('hovering shows which node a click would select', async () => {
			const { page, context } = await open(app, 'chromium', 'dev', '/', { width: 1280, height: 800 });
			await present(page);
			const box = (await canvas(page).boundingBox())!;
			await page.mouse.move(box.x + box.width / 2, box.y + (270 / 1280) * box.width);
			expect(await page.locator('.box.hover').count()).toBe(1);
			await context.close();
		});

		test('the screenshot zooms up to four times around the pointer', async () => {
			const { page, context } = await open(app, 'chromium', 'dev', '/', { width: 1280, height: 800 });
			await present(page);
			const before = (await canvas(page).boundingBox())!;
			await page.mouse.move(before.x + before.width / 2, before.y + before.height / 2);
			await page.keyboard.down('Control');
			for (let step = 0; step < 30; step++) await page.mouse.wheel(0, -100);
			await page.keyboard.up('Control');
			const after = (await canvas(page).boundingBox())!;
			expect(after.width / before.width).toBeCloseTo(4, 5);
			await tap(page, 320 + 100, 270);
			expect(await page.locator('.selected').innerText()).toBe('ListRow');
			await context.close();
		});

		test('closing gives focus back to the field that had it', async () => {
			const { page, context } = await open(app, 'chromium', 'dev', '/lists/groceries');
			await page.getByRole('textbox', { name: 'New todo' }).fill('Kiwi');
			// The click that opens the editor must not take focus from the field either.
			await page.getByRole('heading', { level: 1 }).click({ modifiers: ['Alt', 'Meta'] });
			await editor(page).waitFor();
			await page.getByRole('button', { name: 'Close' }).click();
			await editor(page).waitFor({ state: 'detached' });
			expect(await page.evaluate(() => document.activeElement?.getAttribute('aria-label'))).toBe('New todo');
			await context.close();
		});

		test('leaving the page clears the pill at once', async () => {
			const { page, context } = await open(app, 'chromium', 'dev', '/');
			await page.evaluate(() => globalThis.__feedbackEngine!.showPill());
			await page.getByRole('button', { name: 'Add Feedback' }).waitFor();
			await page.evaluate(() => {
				Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
				document.dispatchEvent(new Event('visibilitychange'));
			});
			await page.getByRole('button', { name: 'Add Feedback' }).waitFor({ state: 'detached', timeout: 1000 });
			await context.close();
		});

		test('posting to ProcrastiMate creates one task with the image and the JSON attached', async () => {
			procrastimate.tasks.length = 0;
			const { page, context, errors } = await open(app, 'chromium', 'dev', '/');
			await present(page);
			await tap(page, 100, 270);
			await field(page).fill('Row is too tall');
			await field(page).press('Enter');
			await page.getByRole('button', { name: 'Share' }).click();
			await page.getByRole('menuitem', { name: 'ProcrastiMate' }).click();

			const sheet = page.getByRole('form', { name: 'Add to ProcrastiMate' });
			const name = sheet.getByRole('textbox', { name: 'Task name' });
			expect(await name.inputValue()).toBe('Lists Feedback: 1 change');
			await sheet.getByRole('option', { name: 'Todo app' }).waitFor();
			expect(await sheet.getByRole('option').allInnerTexts()).toEqual(['Inbox\n✓', 'Todo app', 'Later']);
			await sheet.getByRole('option', { name: 'Todo app' }).click();
			expect(await sheet.getByRole('option').allInnerTexts()).toEqual([
				'Inbox',
				'Todo app',
				'No section\n✓',
				'Bugs',
				'Polish',
				'Later',
			]);
			await sheet.getByRole('option', { name: 'Bugs' }).click();
			await name.fill('Shorter rows');
			await sheet.getByRole('button', { name: 'Add' }).click();

			const toast = page.locator('.toast');
			await toast.waitFor();
			expect(await toast.innerText()).toBe('✓ Added to Todo app / Bugs in ProcrastiMate ↗');
			expect(procrastimate.unauthorized).toBe(0);
			expect(procrastimate.tasks.length).toBe(1);
			const [task] = procrastimate.tasks;
			expect({ title: task!.title, projectId: task!.projectId, sectionId: task!.sectionId }).toEqual({
				title: 'Shorter rows',
				projectId: 'p1',
				sectionId: 's1',
			});
			const [image, report] = task!.attachments as {
				id: string;
				width?: number;
				height?: number;
				name?: string;
				type?: string;
				bytes?: number;
			}[];
			// The image export is 1,070 points wide at 2x, and the upload fits its width to 2,048 pixels.
			expect(image!.width).toBe(2048);
			expect(procrastimate.uploads.get(`${image!.id}/full`)!.type).toBe('image/jpeg');
			expect(procrastimate.uploads.get(`${image!.id}/full`)!.bytes).toBeLessThanOrEqual(1_500_000);
			expect(procrastimate.uploads.get(`${image!.id}/thumb`)!.bytes).toBeLessThanOrEqual(200_000);
			expect({ name: report!.name, type: report!.type }).toEqual({ name: 'feedback.json', type: 'application/json' });
			expect(procrastimate.uploads.get(`${report!.id}/part0`)).toEqual({
				type: 'application/octet-stream',
				bytes: report!.bytes!,
			});

			const popup = context.waitForEvent('page');
			await toast.getByRole('button').click();
			expect((await popup).url()).toBe('https://procrastimate.stf.lol/inbox?task=task-1');

			await page.getByRole('button', { name: 'Close' }).click();
			await editor(page).waitFor({ state: 'detached' });
			expect(errors).toEqual([]);
			await context.close();
		});

		test('a scroll container inside the page shows only what was on screen in it', async () => {
			const { page, context } = await open(app, 'chromium', 'dev', '/catalog');
			await page.locator('.featured').evaluate(node => node.scrollTo({ left: 150 }));
			await present(page);
			const report = await exportReport(page);
			const carousel = report.nodes.find(node => node.name === 'Featured')!;
			const plans = report.nodes.filter(node => node.parent === carousel.id);
			// The carousel is 358 points wide and each plan 112 with an 8 point gap, so 150 points in, plans 2 to 5 show.
			expect(plans.map(plan => plan.label)).toEqual(['Plan 2', 'Plan 3', 'Plan 4', 'Plan 5']);
			expect(plans.map(plan => [plan.frame.x, plan.frame.width])).toEqual([
				[16, 82],
				[106, 112],
				[226, 112],
				[346, 28],
			]);
			await context.close();
		});

		test('a dialog inside a fixed shell is still its own layer', async () => {
			const { page, context, errors } = await open(app, 'chromium', 'dev', '/');
			await page.evaluate(() => {
				const shell = document.createElement('div');
				shell.style.cssText = 'position: fixed; top: 0; right: 0; left: 0; height: 40px; background: #334';
				shell.innerHTML = '<button>Shell</button><dialog style="margin: auto"><button>Inside</button></dialog>';
				document.body.append(shell);
				shell.querySelector('dialog')!.showModal();
			});
			await present(page);
			const report = await exportReport(page);
			expect(outline(report, 1)).toEqual(['  Dialog', '    Button "Inside"']);
			expect(report.nodes.find(node => node.label === 'Shell')!.layer).toBe(0);
			const inside = report.nodes.find(node => node.label === 'Inside')!.frame;
			await tap(page, inside.x + 5, inside.y + 5);
			expect(await page.locator('.selected').innerText()).toBe('Button "Inside"');
			expect(errors).toEqual([]);
			await context.close();
		});

		test('context named like an environment entry shows beside it in the list', async () => {
			const { page, context, errors } = await open(app, 'chromium', 'dev', '/');
			await page.evaluate(() => globalThis.__feedbackEngine!.context('App', () => ({ build: 7 })));
			await present(page);
			await page.getByRole('button', { name: /^Feedback list/ }).click();
			const names = await page.getByRole('dialog', { name: 'Feedback list' }).locator('summary').allInnerTexts();
			expect(names.filter(name => name === 'App').length).toBe(2);
			expect(errors).toEqual([]);
			await context.close();
		});

		test('an open popover menu is a layer, and the screenshot draws it', async () => {
			const { page, context, errors } = await open(app, 'chromium', 'dev', '/lists/groceries');
			await page.getByRole('button', { name: 'Sort' }).click();
			await page.getByRole('menu', { name: 'Sort' }).waitFor();
			const window = await page.screenshot();
			await present(page);
			const capture = await captureImage(page);
			const report = await exportReport(page);
			expect(outline(report, 1)).toEqual([
				'  Menu',
				expected[app].sortMenu,
				'      Menu item "manual"',
				'      Menu item "due date"',
				'      Menu item "priority"',
			]);
			const menu = report.nodes.find(node => node.kind === 'layer')!.frame;
			const pixels = {
				x: menu.x * 2,
				y: menu.y * 2,
				width: Math.floor(menu.width * 2),
				height: Math.floor(menu.height * 2),
			};
			expect(difference(capture, window, 0, pixels)).toBeLessThan(0.05);
			expect(errors).toEqual([]);
			await context.close();
		});

		test.if(app === 'react')('a capture survives a change in React that breaks the component reader', async () => {
			const { page, context, errors } = await open(app, 'chromium', 'dev', '/');
			// What React keeps on its root element, in a shape the reader does not know. The tagged screen and the elements stay.
			await page.evaluate(() => Object.assign(document.body, { __reactContainer$changed: {} }));
			await present(page);
			const report = await exportReport(page);
			expect(outline(report).slice(0, 6)).toEqual([
				'Screen',
				'  ListsScreen  src/screens/ListsScreen.tsx:26',
				'    Header "Lists"',
				'    Button "New List"',
				'    Text "21"',
				'    Text "1"',
			]);
			expect(errors).toEqual([]);
			await context.close();
		});

		test('charts, images, and toFeedback() on the media screen', async () => {
			const { page, context, errors } = await open(app, 'chromium', 'dev', '/media');
			await page.waitForLoadState('networkidle');
			const window = await page.screenshot();
			await present(page);
			expect(difference(await captureImage(page), window, 0)).toBeLessThan(0.02);
			const report = await exportReport(page);
			expect(report.nodes.find(node => node.name === 'OpenChart')!.data).toBe('series: Open per list: 17, 3, 1');
			expect(report.nodes.find(node => node.name === 'DoneChart')!.data).toBe('series: Done per list: 2, 0, 1');
			// An image with an empty alt is decorative, so it is not an element.
			expect(report.nodes.filter(node => node.name === 'Image').map(node => node.label)).toEqual([
				'Open todos per list',
				'Feedback icon',
				'Feedback icon from another origin',
			]);
			expect(errors).toEqual([]);
			await context.close();
		});
	});
}
