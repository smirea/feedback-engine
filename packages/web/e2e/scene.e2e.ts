import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import { appNames, capture, difference, engineNames, open, outline, startServers, stopServers } from './app.ts';

beforeAll(startServers, 60_000);
afterAll(stopServers);

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
		detailDialog: '    TodoDetailDialog  src/lib/TodoDetailDialog.svelte:24',
		sortMenu: '    SortMenu  src/routes/lists/[id]/+page.svelte:84',
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
		detailDialog: '    TodoDetailDialog  src/components/TodoDetailDialog.tsx:7',
		sortMenu: '    SortMenu  src/screens/ListDetailScreen.tsx:116',
	},
};

for (const app of appNames) {
	for (const engine of engineNames) {
		describe(`the ${app} example in ${engine}`, () => {
			test('a page is read into its components, with their sources and data, and the elements in them', async () => {
				const { page, context, errors } = await open(app, engine, '/');
				const { report } = await capture(page);
				expect(outline(report)).toEqual(expected[app].lists);
				const node = (title: string) =>
					report.nodes.find(candidate => `${candidate.name} "${candidate.label}"` === title)!;
				expect(node('Button "New List"').source).toBe(expected[app].newListButton);
				expect(report.nodes.find(candidate => candidate.name === 'ListRow')!.data).toBe(
					'name: Groceries\nremaining: 17\ntotal: 19',
				);
				expect(report.nodes.filter(candidate => candidate.name === 'Stat').map(stat => stat.data)).toEqual([
					'value: 21\nlabel: Open',
					'value: 1\nlabel: Due today',
					'value: 3\nlabel: Lists',
				]);
				expect(errors).toEqual([]);
				await context.close();
			});

			test('a scrolled page is captured at full length, with fixed content where it was on screen', async () => {
				const { page, context, errors } = await open(app, engine, '/timeline');
				await page.evaluate(() => scrollTo(0, 1500));
				const window = await page.screenshot();
				const { report, image } = await capture(page);
				expect(await page.evaluate(() => scrollY)).toBe(1500);

				// Text is drawn a little differently in a canvas than on screen, more so on Linux than on macOS.
				expect(difference(image, window, 1500 * 2)).toBeLessThan(0.01);
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
				const { page, context, errors } = await open(app, engine, '/lists/groceries');
				await page.evaluate(() => scrollTo(0, 300));
				await page.getByRole('button', { name: 'Bananas' }).click();
				await page.getByRole('heading', { name: 'Details' }).waitFor();
				await page.locator(':focus').blur();
				const window = await page.screenshot();
				const { report, image } = await capture(page);

				expect(difference(image, window, 300 * 2)).toBeLessThan(0.02);
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
				expect(errors).toEqual([]);
				await context.close();
			});

			test('a scroll container inside the page shows only what was on screen in it', async () => {
				const { page, context, errors } = await open(app, engine, '/catalog');
				await page.locator('.featured').evaluate(node => node.scrollTo({ left: 150 }));
				const { report } = await capture(page);
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
				expect(errors).toEqual([]);
				await context.close();
			});

			test('a dialog inside a fixed shell is still its own layer', async () => {
				const { page, context, errors } = await open(app, engine, '/');
				await page.evaluate(() => {
					const shell = document.createElement('div');
					shell.style.cssText = 'position: fixed; top: 0; right: 0; left: 0; height: 40px; background: #334';
					shell.innerHTML = '<button>Shell</button><dialog style="margin: auto"><button>Inside</button></dialog>';
					document.body.append(shell);
					shell.querySelector('dialog')!.showModal();
				});
				const { report } = await capture(page);
				expect(outline(report, 1)).toEqual(['  Dialog', '    Button "Inside"']);
				expect(report.nodes.find(node => node.label === 'Shell')!.layer).toBe(0);
				expect(errors).toEqual([]);
				await context.close();
			});

			test('an open popover menu is a layer, and the screenshot draws it', async () => {
				const { page, context, errors } = await open(app, engine, '/lists/groceries');
				await page.getByRole('button', { name: 'Sort' }).click();
				await page.getByRole('menu', { name: 'Sort' }).waitFor();
				const window = await page.screenshot();
				const { report, image } = await capture(page);
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
				expect(difference(image, window, 0, pixels)).toBeLessThan(0.05);
				expect(errors).toEqual([]);
				await context.close();
			});

			test('charts and images are read with their labels and toFeedback() values, and a decorative image is left out', async () => {
				const { page, context, errors } = await open(app, engine, '/media');
				await page.waitForLoadState('networkidle');
				const window = await page.screenshot();
				const { report, image } = await capture(page);
				expect(difference(image, window, 0)).toBeLessThan(0.02);
				expect(report.nodes.find(node => node.name === 'OpenChart')!.data).toBe('series: Open per list: 17, 3, 1');
				expect(report.nodes.find(node => node.name === 'DoneChart')!.data).toBe('series: Done per list: 2, 0, 1');
				expect(report.nodes.filter(node => node.name === 'Image').map(node => node.label)).toEqual([
					'Open todos per list',
					'Feedback icon',
					'Feedback icon from another origin',
				]);
				expect(errors).toEqual([]);
				await context.close();
			});

			test.if(app === 'react')(
				'a change in React that breaks the component reader still leaves the tagged components and the elements',
				async () => {
					const { page, context, errors } = await open(app, engine, '/');
					// What React keeps on its root element, in a shape the reader does not know.
					await page.evaluate(() => Object.assign(document.body, { __reactContainer$changed: {} }));
					const { report } = await capture(page);
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
				},
			);
		});
	}
}
