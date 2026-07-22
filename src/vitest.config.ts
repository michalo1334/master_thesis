import { defineConfig } from "vitest/config";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import { svelteTesting } from "@testing-library/svelte/vite";

export default defineConfig({
  plugins: [
    svelte({ compilerOptions: { css: "injected" } }),
    svelteTesting(),
  ],
  resolve: {
    alias: {
      "@": ".",
    },
  },
  test: {
    environment: "jsdom",
    include: ["assets/svelte/dashboard/**/*.svelte.test.ts"],
    setupFiles: ["assets/svelte/test-setup.ts"],
  },
});
