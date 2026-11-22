#!/usr/bin/env node
import { existsSync, lstatSync, mkdirSync, readFileSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';

const name = '@stefan.inc/feedback-engine';
const skill = 'feedback-accessibility';
const start = '<!-- feedback-engine:start -->';
const end = '<!-- feedback-engine:end -->';

const usage = `Usage: feedback-engine init

Run it from the root of an app that has ${name} installed. It links the package's
${skill} skill into .agents/skills, and adds a section to AGENTS.md that tells the app's
agents about the skill, the editor, and __feedbackEngine.capture(). Run it again after an
upgrade: the skill follows the installed version through the link, and the section is replaced.`;

function fail(message) {
	console.error(`feedback-engine: ${message}`);
	process.exit(1);
}

/** The installed package, through node_modules rather than its real path, so the link survives an upgrade. */
function installed(root) {
	for (let folder = root; ; folder = dirname(folder)) {
		const candidate = join(folder, 'node_modules', name);
		if (existsSync(join(candidate, 'package.json'))) return candidate;
		if (dirname(folder) === folder) fail(`${name} is not installed here. Add it first: bun add ${name}`);
	}
}

function link(root, source) {
	const target = join(root, '.agents', 'skills', skill);
	mkdirSync(dirname(target), { recursive: true });
	const existing = lstatSync(target, { throwIfNoEntry: false });
	if (existing && !existing.isSymbolicLink()) {
		fail(`${relative(root, target)} already exists and is not a link. Remove it, and init links the installed skill.`);
	}
	if (existing) unlinkSync(target);
	// A relative link works in every clone of the app. Windows links folders only as junctions, which need an absolute path.
	if (process.platform === 'win32') symlinkSync(source, target, 'junction');
	else symlinkSync(relative(dirname(target), source), target, 'dir');
	return target;
}

function section(root) {
	const manifest = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
	const dependencies = { ...manifest.dependencies, ...manifest.devDependencies };
	const framework = dependencies.svelte && !dependencies.react ? 'Svelte' : 'React';
	const run = existsSync(join(root, 'bun.lock')) || existsSync(join(root, 'bun.lockb')) ? 'bun' : 'node';
	return `${start}
## Feedback

This app uses [Feedback](https://github.com/smirea/feedback-engine/tree/master/packages/web) (\`${name}\`) to collect feedback on its screens. In the running app, Alt+Meta+click anything to open the editor on it. An export someone hands you, \`feedback.png\`, \`feedback.json\`, or a ZIP of both, names the component or element of each note and its \`file:line\`. [The report format](https://github.com/smirea/feedback-engine/blob/master/spec/report.md) describes the JSON.

- When you build or change a ${framework} screen, row, card, or chart, follow the \`${skill}\` skill: \`.agents/skills/${skill}/SKILL.md\`.
- To see a screen as Feedback reads it, open it in a browser and run \`await page.evaluate(() => __feedbackEngine.capture())\`. It returns the JSON export without opening the editor. Save it as \`feedback.json\`, and \`${run} .agents/skills/${skill}/scripts/taps.js feedback.json\` replays every tap on it.
${end}`;
}

/** Replaces the section between the markers, or appends it, and leaves the rest of the file as it was. */
function write(file, text) {
	const current = existsSync(file) ? readFileSync(file, 'utf8') : '';
	const from = current.indexOf(start);
	const to = current.indexOf(end);
	if ((from === -1) !== (to === -1) || to < from)
		fail(`${file} has only one of the feedback-engine markers. Fix it by hand.`);
	const next =
		from === -1
			? `${current}${current && !current.endsWith('\n') ? '\n' : ''}${current ? '\n' : ''}${text}\n`
			: `${current.slice(0, from)}${text}${current.slice(to + end.length)}`;
	if (next !== current) writeFileSync(file, next);
	return next !== current;
}

const [command, ...rest] = process.argv.slice(2);
if (command === '--help' || command === '-h') {
	console.log(usage);
	process.exit(0);
}
if (command !== 'init' || rest.length > 0) fail(`unknown command.\n\n${usage}`);

const root = resolve('.');
if (!existsSync(join(root, 'package.json'))) fail('run init from the folder that holds the app’s package.json.');
const source = join(installed(root), 'skills', skill);
if (!existsSync(join(source, 'SKILL.md'))) fail(`${source} has no SKILL.md. Upgrade ${name}.`);

const linked = link(root, source);
console.log(`Linked ${relative(root, linked)} to ${relative(root, source)}`);

const text = section(root);
const files = [join(root, 'AGENTS.md')];
// Claude Code reads CLAUDE.md and not AGENTS.md, unless CLAUDE.md points to it.
const claude = join(root, 'CLAUDE.md');
if (existsSync(claude) && !readFileSync(claude, 'utf8').includes('AGENTS.md')) files.push(claude);
for (const file of files) console.log(`${write(file, text) ? 'Updated' : 'Unchanged'} ${relative(root, file)}`);
