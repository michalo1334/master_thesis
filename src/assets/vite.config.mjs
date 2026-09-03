import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import liveSveltePlugin from "live_svelte/vitePlugin";
import tailwindcss from "@tailwindcss/vite";

const sharedHmrToken = {
  name: "shared-hmr-token",
  configResolved(config) {
    // HAProxy routes HMR upgrades to any identical Vite server without affinity.
    config.webSocketToken = "network-defense-local";
  },
};

export default defineConfig(({ command }) => ({
  // Dev server and build use separate cacheDirs to prevent build from
  // clobbering the dev server's pre-bundled deps.
  cacheDir: command === "build" ? "/app/_build_docker/vite-build" : "/app/_build_docker/vite",
  server: {
    host: "0.0.0.0",
    port: 5173,
    strictPort: true,
    cors: { origin: "http://localhost:4000" },
    hmr: { clientPort: 4000 },
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
    noExternal: process.env.NODE_ENV === "production" ? true : undefined,
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
    sharedHmrToken,
  ],
}));
