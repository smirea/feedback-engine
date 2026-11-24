import { withFeedbackEngine } from "@stefan.inc/feedback-engine/next";

const engine = "./node_modules/@stefan.inc/feedback-engine/src";

// A deployed preview, where a person gives feedback on a production build, so the elements keep their `file:line`.
export default withFeedbackEngine(
  {
    turbopack: {
      resolveAlias: {
        "feedback-capture": `${engine}/dom/capture.ts`,
        "feedback-core": `${engine}/core/index.ts`,
      },
    },
  },
  { elementSources: true },
);
