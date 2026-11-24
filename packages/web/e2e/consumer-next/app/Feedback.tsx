"use client";

import { setupFeedbackEngine } from "@stefan.inc/feedback-engine/react";
import { useEffect } from "react";
import "./capture.js";

export function Feedback() {
  useEffect(() => setupFeedbackEngine({ app: "Consumer", button: true }).destroy, []);
  return null;
}
