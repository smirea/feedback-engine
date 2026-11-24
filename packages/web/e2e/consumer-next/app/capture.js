// Captures the page the way the editor does, through the installed package's own modules, so the tests read the tree
// without driving the editor. The aliases in `next.config.ts` point into the package, which keeps Next's type check out
// of its source, and Turbopack gives this file and the package's entry point one copy of each module.
import { captureScreen } from "feedback-capture";
import { Annotations, reportJSON } from "feedback-core";

globalThis.captureReport = async () =>
  reportJSON((await captureScreen({ context: [] })).capture, new Annotations());
