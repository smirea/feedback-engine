#!/usr/bin/env bun
import worker from './worker.ts';

const { GITHUB_TOKEN, GITHUB_REPO, WEBHOOK_KEY, PORT = '8787' } = process.env;
if (!GITHUB_TOKEN || !GITHUB_REPO) throw new Error('Set GITHUB_TOKEN and GITHUB_REPO, such as GITHUB_REPO=owner/name.');

// On every interface, so a phone or a simulator on the same network reaches it too.
const server = Bun.serve({
	port: Number(PORT),
	hostname: '0.0.0.0',
	fetch: request => worker.fetch(request, { GITHUB_TOKEN, GITHUB_REPO, WEBHOOK_KEY }),
});
console.log(`Feedback posts to http://localhost:${server.port} become issues in ${GITHUB_REPO}.`);
