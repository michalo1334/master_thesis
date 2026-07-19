import { defineConfig } from "vitest/config";
import { svelte } from "@sveltejs/vite-plugin-svelte";

export default defineConfig({
  plugins: [svelte({ compilerOptions: { css: "injected" } })],
  resolve: {
    alias: {
      "@": ".",
    },
  },
  test: {
    include: ["assets/svelte/dashboard/**/*.svelte.test.ts"],
  },
});
