import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import liveSveltePlugin from "live_svelte/vitePlugin";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  server: {
    host: "0.0.0.0",
    port: 5173,
    strictPort: true,
    cors: { origin: "http://localhost:4000" },
  },
  optimizeDeps: {
    include: [
      "live_svelte",
      "phoenix",
      "phoenix_html",
      "phoenix_live_view",
      "d3-force",
    ],
  },
  ssr: {
    noExternal:
      process.env.NODE_ENV === "production" ? true : undefined,
  },
  build: {
    manifest: true,
    rollupOptions: {
      input: ["js/app.ts", "css/app.css"],
    },
    outDir: "../priv/static",
    emptyOutDir: true,
  },
  resolve: {
    alias: {
      "@": ".",
      "phoenix-colocated": `${process.env.MIX_BUILD_PATH}/phoenix-colocated`,
    },
  },
  plugins: [
    tailwindcss(),
    svelte({ compilerOptions: { css: "injected" } }),
    liveSveltePlugin({ entrypoint: "./js/server.ts" }),
  ],
});
