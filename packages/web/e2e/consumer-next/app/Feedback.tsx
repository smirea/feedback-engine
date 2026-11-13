'use client';

import { setupFeedbackEngine } from '@stefan.inc/feedback-engine/react';
import { useEffect } from 'react';

export function Feedback() {
	useEffect(() => setupFeedbackEngine({ app: 'Consumer', button: true }).destroy, []);
	return null;
}
