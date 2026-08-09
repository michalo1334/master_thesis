import "@testing-library/jest-dom/vitest";
import { afterEach } from "vitest";

// Bits UI defers body-scroll cleanup by 24ms after a dialog unmounts.
afterEach(() => new Promise((resolve) => setTimeout(resolve, 25)));
