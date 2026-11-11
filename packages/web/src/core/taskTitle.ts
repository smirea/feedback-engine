import type { FeedbackItem } from './annotations.ts';
import { title, type Capture } from './model.ts';

export const taskTitleInstructions =
	'You name tasks for a developer. Given feedback items about an app screen, reply with one lowercase phrase of at ' +
	'most 8 words that covers every item, such as "bigger titles, remove the share button". No quotes, no trailing ' +
	'period, no preamble.';

/** A ProcrastiMate task's name: `<screen> Feedback: N changes` at first, then `N <screen> Feedback: <summary>` once a model has summarized the items. */
export function taskTitle(capture: Capture, items: FeedbackItem[]) {
	const subject = [capture.screenName ?? capture.environment.find(entry => entry.name === 'App')?.value, 'Feedback']
		.filter(Boolean)
		.join(' ');
	const count = items.length;
	return {
		subject,
		count,
		prompt: items
			.map(
				item =>
					`- On ${title(capture.nodes[item.target]!)}: ${item.text
						.split(/[\r\n]+/)
						.filter(Boolean)
						.join(' ')}`,
			)
			.join('\n'),
		placeholder: `${subject}: ${count} ${count === 1 ? 'change' : 'changes'}`,
		/** The model's reply on one line without the wrapping it sometimes adds. `undefined` when nothing is left, so the placeholder stays. */
		summarized(reply: string) {
			const line = reply.split(/[\r\n]+/).find(Boolean) ?? '';
			const summary = line.replace(/^[\s"'“”‘’`*]+|[\s"'“”‘’`*]+$/g, '').replace(/^[.\s]+|[.\s]+$/g, '');
			return summary ? `${count} ${subject}: ${summary}` : undefined;
		},
	};
}
