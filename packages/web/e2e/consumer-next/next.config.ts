import { withFeedbackEngine } from '@stefan.inc/feedback-engine/next';

// A deployed preview, where a person gives feedback on a production build, so the elements keep their `file:line`.
export default withFeedbackEngine({}, { elementSources: true });
