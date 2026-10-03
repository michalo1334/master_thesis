import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import liveSveltePlugin from "live_svelte/vitePlugin";
import tailwindcss from "@tailwindcss/vite";

const phxHost = process.env.PHX_HOST || "localhost";
const publicPortValue = process.env.PHX_PUBLIC_PORT ?? "4000";

if (!/^\d+$/.test(publicPortValue)) {
  throw new Error(
    `PHX_PUBLIC_PORT must be a valid port, got ${JSON.stringify(publicPortValue)}`,
  );
}

const publicPort = Number(publicPortValue);

if (!Number.isSafeInteger(publicPort) || publicPort < 1 || publicPort > 65535) {
  throw new Error(
    `PHX_PUBLIC_PORT must be between 1 and 65535, got ${JSON.stringify(publicPortValue)}`,
  );
}

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
    cors: { origin: `http://${phxHost}:${publicPort}` },
    hmr: { clientPort: publicPort },
  },
  optimizeDeps: {
    include: [
      "live_svelte",
      "phoenix",
      "phoenix_html",
      "phoenix_live_view",
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
