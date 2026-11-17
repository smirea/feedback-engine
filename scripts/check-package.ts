#!/usr/bin/env bun
// Fails when the published tarball holds anything but the source, the manifest, the README, and the license.
import { join } from 'node:path';

const result = Bun.spawnSync(['npm', 'pack', '--dry-run', '--json'], { cwd: join(import.meta.dir, '../packages/web') });
if (result.exitCode !== 0) throw new Error(result.stderr.toString());
// npm 12 keys the result by package name, and earlier versions return an array.
const [{ files }] = Object.values(JSON.parse(result.stdout.toString())) as [{ files: { path: string }[] }];
const paths = files.map(file => file.path);
const unexpected = paths.filter(
	path => !['LICENSE', 'README.md', 'package.json'].includes(path) && !/^src\/.+\.(ts|js|svelte)$/.test(path),
);
const tests = paths.filter(path => path.endsWith('.test.ts'));
const missing = ['LICENSE', 'README.md', 'package.json', 'src/svelte/index.ts'].filter(path => !paths.includes(path));
if (unexpected.length + tests.length + missing.length > 0) {
	console.error(
		`The packed package is wrong.\nUnexpected: ${[...unexpected, ...tests].join(', ')}\nMissing: ${missing.join(', ')}`,
	);
	process.exit(1);
}
