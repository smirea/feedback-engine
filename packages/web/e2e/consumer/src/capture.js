// Captures the page the way the editor does, through the installed package's own modules, so the tests read the tree
// without driving the editor. The bundler gives this file and the package's entry point one copy of each module.
import { Annotations, reportJSON } from "@stefan.inc/feedback-engine/core";
import { captureScreen } from "../node_modules/@stefan.inc/feedback-engine/src/dom/capture.ts";

globalThis.captureReport = async () =>
  reportJSON((await captureScreen({ context: [] })).capture, new Annotations());
