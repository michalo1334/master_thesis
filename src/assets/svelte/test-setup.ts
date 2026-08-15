import "@testing-library/jest-dom/vitest";
import { afterEach, vi } from "vitest";

vi.stubGlobal(
  "ResizeObserver",
  class {
    observe() {}
    unobserve() {}
    disconnect() {}
  },
);

// Bits UI defers body-scroll cleanup by 24ms after a dialog unmounts.
afterEach(() => new Promise((resolve) => setTimeout(resolve, 25)));
