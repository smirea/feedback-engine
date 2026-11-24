import { parseSavedWebhooks, type SavedWebhook } from "../core/savedWebhooks.ts";

/** The page's origin keeps them, so every page of the app lists them, and another app on another origin does not. */
const key = "feedback-engine.webhooks";

/** A browser that blocks storage, such as one with cookies off, lists none. */
export function loadSavedWebhooks(): SavedWebhook[] {
  try {
    return parseSavedWebhooks(localStorage.getItem(key));
  } catch {
    return [];
  }
}

/** Throws where the browser keeps nothing, so the dialog can say so. */
export function storeSavedWebhooks(webhooks: SavedWebhook[]) {
  localStorage.setItem(key, JSON.stringify(webhooks));
}
