/**
 * A webhook server for Feedback that files every post as a GitHub issue: the image export at the top, each item with
 * its text and `file:line`, and the JSON export in a collapsed block. `docs/webhooks.md` has the request it reads and
 * how to run it. It uses only `fetch`, so it runs as a Cloudflare Worker and on any other runtime with web requests.
 */
export type Env = {
	/** Writes to the repository: a classic personal access token with the `repo` scope, or `gh auth token`. */
	GITHUB_TOKEN: string;
	/** `owner/name` of the repository the issues go to. */
	GITHUB_REPO: string;
	/** When set, a post must send `Authorization: Bearer <key>`. */
	WEBHOOK_KEY?: string;
};

type Report = {
	environment: { name: string; value: string }[];
	items: { number: number; text: string; title: string; code?: string }[];
};

// A page on another origin sends a preflight for the `Authorization` header and reads the answer only with these.
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Authorization' };
const answer = (status: number, body: object) => Response.json(body, { status, headers: cors });

/** GitHub's limit for an issue's body and for a comment is 65,536 characters. */
const bodyLimit = 65_000;

async function github(env: Env, method: string, url: string, body?: BodyInit, type = 'application/json') {
	const response = await fetch(url, {
		method,
		body,
		headers: {
			Authorization: `Bearer ${env.GITHUB_TOKEN}`,
			Accept: 'application/vnd.github+json',
			'User-Agent': 'feedback-engine-webhook',
			...(body ? { 'Content-Type': type } : {}),
		},
	});
	if (!response.ok) {
		const text = (await response.text()).slice(0, 300);
		throw new Error(`GitHub answered ${response.status} to ${method} ${new URL(url).pathname}: ${text}`);
	}
	return (await response.json()) as Record<string, unknown>;
}

/** A fence longer than any run of backticks inside, so the text cannot close it. */
function fenced(text: string, language = '') {
	const longest = Math.max(0, ...(text.match(/`+/g) ?? []).map(run => run.length));
	const fence = '`'.repeat(Math.max(3, longest + 1));
	return `${fence}${language}\n${text}\n${fence}`;
}

const quoted = (text: string) =>
	text
		.split(/\r?\n/)
		.map(line => `> ${line}`)
		.join('\n');

function issueBody(id: string, title: string, image: string, report: Report) {
	const items = report.items.map(
		item => `**${item.number}. ${item.title}**${item.code ? ` · \`${item.code}\`` : ''}\n\n${quoted(item.text)}`,
	);
	const environment = report.environment.map(entry => `${entry.name}: ${entry.value}`).join(' · ');
	return [`![${title}](${image})`, ...items, environment, `<!-- feedback post ${id} -->`].filter(Boolean).join('\n\n');
}

const collapsed = (summary: string, text: string) =>
	`<details>\n<summary>${summary}</summary>\n\n${fenced(text, 'json')}\n\n</details>`;

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
		if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
		if (request.method !== 'POST') return answer(405, { message: 'Send a POST.' });
		if (!env.GITHUB_TOKEN || !env.GITHUB_REPO) return answer(500, { message: 'Set GITHUB_TOKEN and GITHUB_REPO.' });
		if (env.WEBHOOK_KEY && request.headers.get('authorization') !== `Bearer ${env.WEBHOOK_KEY}`) {
			return answer(401, { message: 'The key is wrong.' });
		}
		const form = await request.formData().catch(() => undefined);
		const [id, title, image, file] = ['id', 'title', 'image', 'report'].map(name => form?.get(name));
		if (typeof id !== 'string' || typeof title !== 'string' || !(image instanceof File) || !(file instanceof File)) {
			return answer(400, { message: 'Send multipart/form-data with id, title, image, and report.' });
		}
		try {
			const json = await file.text();
			const report = JSON.parse(json) as Report;
			const api = `https://api.github.com/repos/${env.GITHUB_REPO}`;
			const repository = await github(env, 'GET', api);
			// The endpoint the GitHub CLI's `--attach` uses. It takes images and video, and a token that can write to the repository.
			const upload = new URL('https://uploads.github.com/user-attachments/assets');
			upload.search = String(
				new URLSearchParams({ name: 'feedback.png', content_type: 'image/png', repository_id: String(repository.id) }),
			);
			const asset = await github(env, 'POST', upload.href, await image.arrayBuffer(), 'application/octet-stream');

			const body = issueBody(id, title, asset.url as string, report);
			const whole = `${body}\n\n${collapsed('feedback.json', json)}`;
			const labels = new URL(request.url).searchParams.get('labels')?.split(',').filter(Boolean);
			const issue = await github(
				env,
				'POST',
				`${api}/issues`,
				JSON.stringify({ title, body: whole.length <= bodyLimit ? whole : body, labels }),
			);
			// A report too long for the issue's body goes into comments, in parts that join back into the file.
			if (whole.length > bodyLimit) {
				const size = bodyLimit - 1000;
				const parts = Math.ceil(json.length / size);
				for (let part = 0; part < parts; part++) {
					const summary = `feedback.json, part ${part + 1} of ${parts}`;
					const comment = collapsed(summary, json.slice(part * size, (part + 1) * size));
					await github(env, 'POST', `${api}/issues/${issue.number}/comments`, JSON.stringify({ body: comment }));
				}
			}
			return answer(201, { url: issue.html_url });
		} catch (error) {
			return answer(502, { message: (error as Error).message });
		}
	},
};
