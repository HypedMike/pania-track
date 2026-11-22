import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Landing page for GitHub Pages, built separately from the Tauri app.
export default defineConfig({
  root: "site",
  envDir: "..",
  base: "/pania-track/",
  plugins: [react()],
  build: { outDir: "../dist-site", emptyOutDir: true },
});
