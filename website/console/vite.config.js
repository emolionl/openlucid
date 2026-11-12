import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";

// The console is its own Firebase Hosting site (target "app", served at app.openlucid.nl).
// firebase.json rewrites every path to index.html, so the router's URLs survive a reload.
export default defineConfig({
  plugins: [vue()],
  build: { outDir: "dist", emptyOutDir: true },
  // ../assets/js/verification.js is shared with the website, so the dev server may read one level up.
  server: { port: 5174, fs: { allow: [".."] } },
});
