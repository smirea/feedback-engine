import { relative, sep } from 'node:path';
import { addReact, compileEditor, packageSource } from '../vite/react.js';

/**
 * The webpack loader that `withFeedbackEngine()` gives Turbopack and webpack. It compiles the editor's Svelte files, and
 * runs `addReact` on the app's `.jsx` and `.tsx` modules.
 *
 * @this {{ resourcePath: string, getOptions(): { root: string, elementSources: boolean, generate: 'client' | 'server' } }}
 * @param {string} code
 */
function feedbackLoader(code) {
	const file = this.resourcePath;
	const options = this.getOptions();
	if (file.endsWith('.svelte'))
		return file.startsWith(packageSource) ? compileEditor(code, file, options.generate).code : code;
	if (file.includes(`${sep}node_modules${sep}`) || file.startsWith(packageSource)) return code;
	return (
		addReact(code, relative(options.root, file).split(sep).join('/'), { elementSources: options.elementSources }) ??
		code
	);
}

export default feedbackLoader;
