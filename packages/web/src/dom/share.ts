import type { Annotations, ImageEncoding } from "../core/index.ts";
import { jpegQuality, reportJSON } from "../core/index.ts";
import type { Screen } from "./capture.ts";
import { annotatedImage } from "./image.ts";
import { zip } from "./zip.ts";

export type ExportFormat = "image" | "data" | "all";

export const exportTitles: Record<ExportFormat, string> = {
  image: "Image",
  data: "Data",
  all: "Image + Data",
};

/** One export: the file to save or share, and the parts the clipboard takes. */
export type Export = { file: File; image?: Blob; json?: string };

export function encodeImage(screen: Screen, annotations: Annotations, encoding: ImageEncoding) {
  const [type, name, quality] =
    encoding.format === "png"
      ? ["image/png", "feedback.png", undefined]
      : ["image/jpeg", "feedback.jpg", jpegQuality[encoding.compression]];
  return new Promise<File>((resolve, reject) =>
    annotatedImage(screen, annotations).toBlob(
      (blob) =>
        blob
          ? resolve(new File([blob], name, { type }))
          : reject(new Error("The browser could not encode the image")),
      type,
      quality,
    ),
  );
}

/** Every export but the image is the data: `feedback.json` and the app's own files, in this order. */
export function dataFiles(screen: Screen, json: string): File[] {
  return [new File([json], "feedback.json", { type: "application/json" }), ...screen.files];
}

async function archive(files: File[]) {
  const entries = await Promise.all(
    files.map(async (file) => ({
      name: `feedback/${file.name}`,
      bytes: new Uint8Array(await file.arrayBuffer()),
    })),
  );
  return new File([await zip(entries)], "feedback.zip", { type: "application/zip" });
}

/** Data is `feedback.json` alone, or a ZIP when the app adds files. Image + Data is always a ZIP. */
export async function buildExport(
  screen: Screen,
  annotations: Annotations,
  format: ExportFormat,
): Promise<Export> {
  const image =
    format === "data" ? undefined : await encodeImage(screen, annotations, { format: "png" });
  if (format === "image") return { file: image!, image };
  const json = reportJSON(screen.capture, annotations);
  const data = dataFiles(screen, json);
  if (format === "data") return { file: data.length === 1 ? data[0]! : await archive(data), json };
  return { file: await archive([image!, ...data]), image, json };
}

/**
 * Puts the export on the clipboard, ready to paste into a chat with an agent. Browsers take one clipboard item per
 * write, so an export with an image and JSON is one item with both, and the paste target picks the one it reads.
 */
export async function copyExport({ image, json }: Export) {
  if (!image) return navigator.clipboard.writeText(json!);
  await navigator.clipboard.write([
    new ClipboardItem({
      "image/png": image,
      ...(json === undefined ? {} : { "text/plain": new Blob([json], { type: "text/plain" }) }),
    }),
  ]);
}

export function saveExport({ file }: Export) {
  const link = document.createElement("a");
  link.href = URL.createObjectURL(file);
  link.download = file.name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(link.href), 60_000);
}

export const canShare = ({ file }: Export) => !!navigator.canShare?.({ files: [file] });

/** Hands the file to the system share sheet. Resolves to `false` when the user backs out of it. */
export async function shareExport({ file }: Export) {
  try {
    await navigator.share({ files: [file] });
    return true;
  } catch (error) {
    if ((error as Error).name === "AbortError") return false;
    throw error;
  }
}
