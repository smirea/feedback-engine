import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const statuses = new Set(['shipped', 'planned', 'no']);
const platforms = ['iOS', 'Svelte', 'React'];

function problems(markdown: string) {
	const found: string[] = [];
	const seen = new Set<string>();
	let columns: string[] = [];
	for (const line of markdown.split('\n').map(row => row.trim())) {
		if (!line.startsWith('|')) continue;
		const cells = line
			.slice(1, -1)
			.split('|')
			.map(cell => cell.trim());
		if (cells[0] === 'ID') {
			columns = cells;
			continue;
		}
		if (/^:?-+:?$/.test(cells[0]!)) continue;
		const row = Object.fromEntries(columns.map((column, index) => [column, cells[index] ?? '']));
		const id = row.ID!;
		if (cells.length !== columns.length) found.push(`${id}: ${cells.length} cells for ${columns.length} columns`);
		if (!id) found.push(`"${row.Feature}": no id`);
		if (seen.has(id)) found.push(`${id}: duplicate id`);
		seen.add(id);
		if (!row.Feature) found.push(`${id}: no feature`);
		for (const platform of platforms) {
			if (!statuses.has(row[platform]!)) found.push(`${id}: ${platform} status "${row[platform]}"`);
		}
		if (platforms.some(platform => row[platform] === 'no') && !row.Notes) found.push(`${id}: a "no" without a reason`);
	}
	return { found, rows: seen.size };
}

test('every feature has a status on every platform', () => {
	const { found, rows } = problems(readFileSync(join(import.meta.dir, 'features.md'), 'utf8'));
	expect(found).toEqual([]);
	expect(rows).toBeGreaterThan(0);
});

test('the check reports a missing status, a duplicate id, a missing id, and a "no" without a reason', () => {
	const table = [
		'| ID | Feature | iOS | Svelte | React | Notes |',
		'| --- | --- | --- | --- | --- | --- |',
		'| T1 | Shake. | shipped | shipped | | |',
		'| T1 | Pill. | shipped | shipped | no | |',
		'| | Timer. | shipped | planned | planned | |',
	].join('\n');
	expect(problems(table).found).toEqual([
		'T1: React status ""',
		'T1: duplicate id',
		'T1: a "no" without a reason',
		'"Timer.": no id',
	]);
});

test('the check reads indented rows and aligned separators', () => {
	const table = [
		'  | ID | Feature | iOS | Svelte | React | Notes |',
		'  | :--- | :---: | --- | --- | --- | ---: |',
		'  | T1 | Shake. | shipped | | shipped | |',
	].join('\n');
	expect(problems(table)).toEqual({ found: ['T1: Svelte status ""'], rows: 1 });
});
