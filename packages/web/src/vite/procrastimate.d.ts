export { feedbackProcrastimate } from './index.js';

type Project = { id: string; name: string };
type View = { projects: Project[]; sections: { id: string; projectId: string }[] };

export function allowedProjectIds(projects: Project[], names: string[]): Set<string>;
export function refusal(
	call: { method: string; route: string; query: URLSearchParams; body: string },
	state: { allowed?: Set<string>; created: Set<string> },
): string | undefined;
export function allowedView(view: View, allowed: Set<string>): View;
