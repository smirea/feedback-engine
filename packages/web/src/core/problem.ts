export type Fact = { label: string; value: string };

const describe = (error: unknown): string =>
	error instanceof Error
		? `${error.name}: ${error.message}${error.cause === undefined ? '' : ` (cause: ${describe(error.cause)})`}`
		: String(error);

/**
 * A failure the editor shows: one line to read, and facts to expand and copy, so a post that fails can be diagnosed
 * without reproducing it. The iOS package's `Problem` has the same facts.
 */
export class Problem extends Error {
	constructor(
		message: string,
		readonly facts: Fact[] = [],
	) {
		super(message);
		this.name = 'Problem';
	}

	/** Keeps a `Problem`'s own facts. Any other error gets its name, message, and cause. */
	static from(error: unknown): Problem {
		if (error instanceof Problem) return error;
		return new Problem(error instanceof Error ? error.message : String(error), [
			{ label: 'Error', value: describe(error) },
		]);
	}

	/** A request that got no answer, or one it could not use. The body is cut at 2,000 characters. */
	static request(method: string, url: string, status: number | undefined, body: string | undefined, error: unknown) {
		const facts: Fact[] = [{ label: 'Request', value: `${method} ${url}` }];
		if (status !== undefined) facts.push({ label: 'Status', value: String(status) });
		if (body) facts.push({ label: 'Response', value: body.length > 2000 ? `${body.slice(0, 2000)}…` : body });
		facts.push({ label: 'Error', value: describe(error) });
		return new Problem(error instanceof Error ? error.message : String(error), facts);
	}

	/** `before` and `after` around the problem's own facts. */
	with(before: Fact[] = [], after: Fact[] = []) {
		return new Problem(this.message, [...before, ...this.facts, ...after]);
	}

	get details() {
		return this.facts.map(fact => `${fact.label}: ${fact.value}`).join('\n');
	}

	/** What Copy puts on the clipboard. */
	get text() {
		return this.facts.length ? `${this.message}\n\n${this.details}` : this.message;
	}
}
