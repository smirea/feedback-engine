import { expect, test } from 'bun:test';
import type * as Real from './index.ts';
import type * as Declared from './public.d.ts';

type Same<A, B> = [A] extends [B] ? ([B] extends [A] ? true : false) : false;

test('the declarations an app compiles against match the entry point', () => {
	const same: [
		Same<typeof Real.setupFeedbackEngine, typeof Declared.setupFeedbackEngine>,
		Same<typeof Real.feedback, typeof Declared.feedback>,
		Same<Real.FeedbackOptions, Declared.FeedbackOptions>,
		Same<Real.FeedbackEngine, Declared.FeedbackEngine>,
		Same<Real.FeedbackRepresentable, Declared.FeedbackRepresentable>,
	] = [true, true, true, true, true];
	expect(same).toEqual([true, true, true, true, true]);
});
