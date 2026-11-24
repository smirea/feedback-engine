import adapter from "@sveltejs/adapter-static";
import { sveltekit } from "@sveltejs/kit/vite";
import tailwindcss from "@tailwindcss/vite";
import { feedbackEngine } from "@stefan.inc/feedback-engine/vite";
import env from "../../env.ts";
import { defineConfig } from "vite";

const uiHost = new URL(env.UI_URL).hostname;

export default defineConfig({
  plugins: [
    tailwindcss(),
    sveltekit({
      preprocess: [feedbackEngine()],
      adapter: adapter({
        fallback: "index.html",
      }),
    }),
  ],
  // The example reads these in the page. Vite hands a page only `VITE_` variables by itself.
  define: {
    "import.meta.env.FEEDBACK_PROCRASTIMATE_APP": JSON.stringify(env.PROCRASTIMATE_URL),
    "import.meta.env.FEEDBACK_PROCRASTIMATE_PROJECT": JSON.stringify(
      env.PROCRASTIMATE_PROJECT ?? "",
    ),
    "import.meta.env.FEEDBACK_PROCRASTIMATE_PROJECTS": JSON.stringify(
      env.PROCRASTIMATE_PROJECTS.split(",")
        .map((name) => name.trim())
        .filter(Boolean),
    ),
    "import.meta.env.FEEDBACK_WEBHOOK_URL": JSON.stringify(env.FEEDBACK_WEBHOOK_URL ?? ""),
    "import.meta.env.FEEDBACK_WEBHOOK_KEY": JSON.stringify(env.FEEDBACK_WEBHOOK_KEY ?? ""),
  },
  clearScreen: false,
  server: {
    allowedHosts: [uiHost],
    port: env.UI_PORT,
    strictPort: true,
  },
  preview: {
    allowedHosts: [uiHost],
    port: env.UI_PORT,
    strictPort: true,
  },
});
