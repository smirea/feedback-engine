/** A file the app adds to every export, made when a capture is taken. */
export type FeedbackFile = {
  /** The file's name in every export, such as `save.json`. */
  name: string;
  /**
   * Makes the file when a capture is taken, so it matches the screenshot. A `Blob` is used as it is, a string as text,
   * and anything else as JSON. `null` or `undefined` leaves the file out, for a screen that has nothing to put in it.
   */
  data: () => unknown;
  /** The media type. Without it, a `Blob` keeps its own, `.json` is `application/json`, and other text is `text/plain`. */
  type?: string;
};

/** A file the app registered that could not be made, and why. */
export type FileFailure = { name: string; error: unknown };

/** How long the editor waits for a file before it opens without it. */
export const fileSeconds = 10;

/** Names the package's own files take in an export. */
const reserved = new Set(["feedback.json", "feedback.png", "feedback.jpg"]);

/** Throws at setup on a name that would collide in a ZIP, so a bad list fails before anyone captures. */
export function checkFiles(files: FeedbackFile[]) {
  const seen = new Set<string>();
  for (const { name } of files) {
    if (!name || name.includes("/"))
      throw new Error(`A feedback file needs a plain file name, not "${name}".`);
    if (reserved.has(name))
      throw new Error(`${name} is Feedback's own file. Give the app's file another name.`);
    if (seen.has(name)) throw new Error(`Two feedback files are named ${name}.`);
    seen.add(name);
  }
}

function toFile({ name, type }: FeedbackFile, value: unknown): File | undefined {
  if (value === null || value === undefined) return undefined;
  if (value instanceof Blob) return new File([value], name, { type: type ?? value.type });
  const json = typeof value !== "string";
  const text = json ? JSON.stringify(value) : value;
  if (text === undefined) throw new Error("It is a value JSON cannot write.");
  return new File([text], name, {
    type: type ?? (json || name.endsWith(".json") ? "application/json" : "text/plain"),
  });
}

/**
 * Starts every generator at once, in the same task as the capture, so each file is the app's state at that moment.
 * A generator that throws, rejects, or takes longer than `fileSeconds` leaves its file out and is reported, so one
 * broken file never blocks feedback.
 */
export async function makeFiles(
  files: FeedbackFile[],
): Promise<{ files: File[]; failures: FileFailure[] }> {
  const results = await Promise.allSettled(
    files.map((file) => {
      try {
        const made = Promise.resolve(file.data()).then((value) => toFile(file, value));
        let timer: ReturnType<typeof setTimeout> | undefined;
        const late = new Promise<never>((_, reject) => {
          timer = setTimeout(
            () => reject(new Error(`It took longer than ${fileSeconds} seconds.`)),
            fileSeconds * 1000,
          );
        });
        return Promise.race([made, late]).finally(() => clearTimeout(timer));
      } catch (error) {
        return Promise.reject(error);
      }
    }),
  );
  const made: File[] = [];
  const failures: FileFailure[] = [];
  results.forEach((result, index) => {
    if (result.status === "rejected")
      failures.push({ name: files[index]!.name, error: result.reason });
    else if (result.value) made.push(result.value);
  });
  return { files: made, failures };
}
