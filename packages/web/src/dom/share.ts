import type { Annotations } from '../core/index.ts';
import { reportJSON } from '../core/index.ts';
import type { Screen } from './capture.ts';
import { annotatedImage } from './image.ts';
import { zip } from './zip.ts';

export type ExportFormat = 'image' | 'json' | 'zip';

export const exportTitles: Record<ExportFormat, string> = {
	image: 'Image',
	json: 'JSON',
	zip: 'Image and JSON (ZIP)',
};

/** One export: the file to save or share, and the parts the clipboard takes. */
export type Export = { file: File; image?: Blob; json?: string };

const toBlob = (canvas: HTMLCanvasElement) =>
	new Promise<Blob>((resolve, reject) =>
		canvas.toBlob(
			blob => (blob ? resolve(blob) : reject(new Error('The browser could not encode the image'))),
			'image/png',
		),
	);

export async function buildExport(screen: Screen, annotations: Annotations, format: ExportFormat): Promise<Export> {
	const image = format === 'json' ? undefined : await toBlob(annotatedImage(screen, annotations));
	const json = format === 'image' ? undefined : reportJSON(screen.capture, annotations);
	if (format === 'image') return { file: new File([image!], 'feedback.png', { type: 'image/png' }), image };
	if (format === 'json') return { file: new File([json!], 'feedback.json', { type: 'application/json' }), json };
	const archive = zip([
		{ name: 'feedback/feedback.png', bytes: new Uint8Array(await image!.arrayBuffer()) },
		{ name: 'feedback/feedback.json', bytes: new TextEncoder().encode(json) },
	]);
	return { file: new File([archive], 'feedback.zip', { type: 'application/zip' }), image, json };
}

/**
 * Puts the export on the clipboard, ready to paste into a chat with an agent. Browsers take one clipboard item per
 * write, so an export with an image and JSON is one item with both, and the paste target picks the one it reads.
 */
export async function copyExport({ image, json }: Export) {
	if (!image) return navigator.clipboard.writeText(json!);
	await navigator.clipboard.write([
		new ClipboardItem({
			'image/png': image,
			...(json === undefined ? {} : { 'text/plain': new Blob([json], { type: 'text/plain' }) }),
		}),
	]);
}

export function saveExport({ file }: Export) {
	const link = document.createElement('a');
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
		if ((error as Error).name === 'AbortError') return false;
		throw error;
	}
}
