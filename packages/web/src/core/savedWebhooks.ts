import type { ContextEntry } from "./model.ts";

export type Compression = "low" | "medium" | "high";

/** Neither a browser's canvas nor UIKit sets a PNG's compression, so only a JPEG has a level. */
export type ImageEncoding = { format: "png" } | { format: "jpeg"; compression: Compression };

/** The JPEG quality of each level, the same on iOS. */
export const jpegQuality: Record<Compression, number> = { low: 0.9, medium: 0.7, high: 0.5 };

/** A webhook someone added in the editor. The device keeps it, and the Share menu lists it after the app's own. */
export type SavedWebhook = {
  id: string;
  name: string;
  url: string;
  header?: { name: string; value: string };
  image?: ImageEncoding;
  feedback: boolean;
};

export type WebhookDraft = {
  name: string;
  url: string;
  header: string;
  image: boolean;
  format: ImageEncoding["format"];
  compression: Compression;
  feedback: boolean;
};

export type DraftErrors = Partial<Record<"name" | "url" | "header", string>>;

export function draftOf(webhook?: SavedWebhook): WebhookDraft {
  return {
    name: webhook?.name ?? "",
    url: webhook?.url ?? "",
    header: webhook?.header ? `${webhook.header.name}: ${webhook.header.value}` : "",
    image: webhook ? !!webhook.image : true,
    format: webhook?.image?.format ?? "png",
    compression: webhook?.image?.format === "jpeg" ? webhook.image.compression : "medium",
    feedback: webhook?.feedback ?? true,
  };
}

const headerPattern = /^([!#$%&'*+.^_`|~0-9A-Za-z-]+)\s*:\s*(\S.*)$/;

/**
 * The webhook a draft describes, or what is wrong with it. `taken` holds the names of the Share menu's other entries,
 * since a name is what `pinned` picks an entry by.
 */
export function readDraft(
  draft: WebhookDraft,
  { id, taken }: { id: string; taken: string[] },
): { webhook: SavedWebhook } | { errors: DraftErrors } {
  const errors: DraftErrors = {};
  const name = draft.name.trim();
  if (!name) errors.name = "Give the webhook a name.";
  else if (taken.some((other) => other.toLowerCase() === name.toLowerCase()))
    errors.name = `The Share menu already has ${name}.`;
  const url = draft.url.trim();
  if (!URL.canParse(url) || !/^https?:$/.test(new URL(url).protocol))
    errors.url = "Enter an address that starts with http:// or https://.";
  const header = draft.header.trim();
  const match = headerPattern.exec(header);
  if (header && !match)
    errors.header = "Write the header as Name: value, such as Authorization: Bearer key.";
  if (Object.keys(errors).length) return { errors };
  return {
    webhook: {
      id,
      name,
      url,
      ...(match ? { header: { name: match[1]!, value: match[2]!.trim() } } : {}),
      ...(draft.image
        ? {
            image:
              draft.format === "jpeg"
                ? { format: "jpeg" as const, compression: draft.compression }
                : { format: "png" as const },
          }
        : {}),
      feedback: draft.feedback,
    },
  };
}

/** The saved webhooks in what the device kept. An entry it cannot read is left out, so one bad entry hides no other. */
export function parseSavedWebhooks(text: string | null): SavedWebhook[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text ?? "[]");
  } catch {
    return [];
  }
  if (!Array.isArray(parsed)) return [];
  return parsed.flatMap((entry: Partial<SavedWebhook>) => {
    if (typeof entry?.id !== "string" || typeof entry.feedback !== "boolean") return [];
    const image = entry.image;
    const read = readDraft(
      {
        name: String(entry.name ?? ""),
        url: String(entry.url ?? ""),
        header: entry.header ? `${entry.header.name}: ${entry.header.value}` : "",
        image: !!image,
        format: image?.format === "jpeg" ? "jpeg" : "png",
        compression:
          image?.format === "jpeg" && image.compression in jpegQuality
            ? image.compression
            : "medium",
        feedback: entry.feedback,
      },
      { id: entry.id, taken: [] },
    );
    return "webhook" in read ? [read.webhook] : [];
  });
}

/** The `device` part of a saved webhook's post: the environment as one object, with sorted keys as on iOS. */
export function deviceJSON(environment: ContextEntry[]) {
  const sorted = environment.toSorted((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  return JSON.stringify(Object.fromEntries(sorted.map((entry) => [entry.name, entry.value])));
}
