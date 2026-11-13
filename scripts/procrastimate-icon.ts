#!/usr/bin/env bun
/**
 * Renders ProcrastiMate's app icon without its tile into the 66 pixel PNG both editors draw on their ProcrastiMate
 * button, 22 points at 3×, and writes it into `packages/web/src/dom/procrastimate-icon.ts` and
 * `packages/ios/Sources/Feedback/ProcrastimateIcon.swift`. Reads `app-web/scripts/app-icon.svg` from the ProcrastiMate
 * checkout given as the first argument, `~/code/procrastimate` by default. Needs `pngquant`.
 */
import { $ } from 'bun';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { chromium } from 'playwright';

const size = 66;
const checkout = process.argv[2] ?? join(homedir(), 'code/procrastimate');
const svg = await Bun.file(join(checkout, 'app-web/scripts/app-icon.svg')).text();
if (!svg.includes('id="tile"')) throw new Error('app-icon.svg has no #tile to drop');

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: size, height: size } });
await page.setContent(`<style>
	html, body { margin: 0; background: transparent; }
	svg { display: block; width: 100vw; height: 100vh; }
	#tile { display: none; }
</style>${svg}`);
const raw = await page.screenshot({ omitBackground: true });
await browser.close();

const png = await $`pngquant --quality 80-95 --strip - < ${raw}`.arrayBuffer();
const base64 = Buffer.from(png).toString('base64');
const root = join(import.meta.dir, '..');
const source = "Rendered by `scripts/procrastimate-icon.ts` from ProcrastiMate's `app-icon.svg`.";

await Bun.write(
	join(root, 'packages/web/src/dom/procrastimate-icon.ts'),
	`/** ProcrastiMate's app icon without its tile, ${size} pixels square for ${size / 3} CSS pixels. ${source} */\nexport const procrastimateIcon = 'data:image/png;base64,${base64}';\n`,
);
await Bun.write(
	join(root, 'packages/ios/Sources/Feedback/ProcrastimateIcon.swift'),
	`#if canImport(UIKit)
import UIKit

/// ProcrastiMate's app icon without its tile, ${size / 3} points at 3×. ${source}
enum ProcrastimateIcon {
    static let image = UIImage(data: Data(base64Encoded: base64)!, scale: 3)!.withRenderingMode(.alwaysOriginal)

    private static let base64 = "${base64}"
}
#endif
`,
);
console.log(`${size}×${size}, ${png.byteLength} bytes`);
