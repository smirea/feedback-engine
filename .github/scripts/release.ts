import { $ } from 'bun';
import { env } from 'node:process';

const tested = env.TESTED_SHA;
if (!tested) throw new Error('Missing TESTED_SHA');

const head = (await $`git rev-parse HEAD`.text()).trim();
if (head !== tested) {
	console.log(`master is at ${head}, past the commit CI tested (${tested}). A later CI run releases what is pending.`);
	process.exit(0);
}

const manifest = 'packages/web/package.json';
const pending = (await $`git ls-files .changeset`.text())
	.split('\n')
	.filter(path => /^\.changeset\/.+\.md$/.test(path));
if (pending.length) {
	await $`bunx changeset version`;
	// `changeset version` leaves the workspace's old version in bun.lock.
	await $`bun install`;
	await $`bunx oxfmt ${manifest}`;
}

const { name, version } = await Bun.file(manifest).json();
// npm answers an unknown version with nothing, and a package it has never seen with E404.
const published = (await $`npm view ${`${name}@${version}`} version`.nothrow().quiet().text()).trim() === version;
// Publishing before pushing lets a rerun converge: a version npm already has is skipped, and its commit is pushed.
if (published) console.log(`${name}@${version} is already on npm.`);
else await $`npm publish`.cwd('packages/web');

if (pending.length) {
	await $`git add --all .changeset packages/web bun.lock`;
	await $`git -c user.name=${'github-actions[bot]'} -c user.email=${'41898282+github-actions[bot]@users.noreply.github.com'} commit -m ${`chore(release): ${name}@${version}`}`;
	const push = await $`git push origin HEAD:master`.nothrow();
	if (push.exitCode !== 0)
		console.log(`master moved while releasing ${version}. The next CI run on master commits the version again.`);
}
