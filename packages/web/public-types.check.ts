// The type check fails here when the declarations an app compiles against drift from the React entry point.
import type * as Real from './src/react/index.ts';
import type * as Declared from './src/react/public.d.ts';

type Same<A, B> = [A] extends [B] ? ([B] extends [A] ? true : false) : false;

export const same: [
	Same<typeof Real.setupFeedbackEngine, typeof Declared.setupFeedbackEngine>,
	Same<typeof Real.feedback, typeof Declared.feedback>,
	Same<Real.FeedbackOptions, Declared.FeedbackOptions>,
	Same<Real.FeedbackEngine, Declared.FeedbackEngine>,
	Same<Real.FeedbackRepresentable, Declared.FeedbackRepresentable>,
	Same<Real.Webhook, Declared.Webhook>,
	Same<Real.WebhookValues, Declared.WebhookValues>,
	Same<typeof Real.githubIcon, typeof Declared.githubIcon>,
	Same<Real.FeedbackReport, Declared.FeedbackReport>,
	Same<Real.FeedbackFile, Declared.FeedbackFile>,
	Same<Required<Real.FeedbackOptions>, Required<Declared.FeedbackOptions>>,
] = [true, true, true, true, true, true, true, true, true, true, true];
