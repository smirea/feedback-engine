import type { FeedbackItem } from "./annotations.ts";
import { title, type Capture } from "./model.ts";

/** @deprecated ProcrastiMate's server names the task now, from `suggestion`. Removed in the next major version. */
export const taskTitleInstructions =
  "You name tasks for a developer. Given feedback items about an app screen, reply with one lowercase phrase of at " +
  'most 8 words that covers every item, such as "bigger titles, remove the share button". No quotes, no trailing ' +
  "period, no preamble.";

/**
 * A ProcrastiMate task's name, `<screen> Feedback: N changes`, and the `suggestion` a post carries while the name is
 * untouched, from which ProcrastiMate's server renames the task `N <screen> Feedback: <summary>`.
 */
export function taskTitle(capture: Capture, items: FeedbackItem[]) {
  const subject = [
    capture.screenName ?? capture.environment.find((entry) => entry.name === "App")?.value,
    "Feedback",
  ]
    .filter(Boolean)
    .join(" ");
  const count = items.length;
  const prompt = items
    .map(
      (item) =>
        `- On ${title(capture.nodes[item.target]!)}: ${item.text
          .split(/[\r\n]+/)
          .filter(Boolean)
          .join(" ")}`,
    )
    .join("\n");
  return {
    subject,
    count,
    prompt,
    placeholder: `${subject}: ${count} ${count === 1 ? "change" : "changes"}`,
    suggestion: { subject, count, prompt },
    /** @deprecated ProcrastiMate's server summarizes now. Removed in the next major version. */
    summarized(reply: string) {
      const line = reply.split(/[\r\n]+/).find(Boolean) ?? "";
      const summary = line
        .replace(/^[\s"'“”‘’`*]+|[\s"'“”‘’`*]+$/g, "")
        .replace(/^[.\s]+|[.\s]+$/g, "");
      return summary ? `${count} ${subject}: ${summary}` : undefined;
    },
  };
}
