import type { StudyRunError } from "../../contracts.generated/dashboard/evaluation";
import { describe, expect, it } from "vitest";
import {
  formatStudyRunError,
  RUN_ERROR_MESSAGES,
  STUDY_PHASE_LABELS,
  STUDY_PHASES,
} from "./study-types";

describe("study-types", () => {
  it("orders the phase list exactly like the exhaustive label map", () => {
    expect(STUDY_PHASES).toEqual(Object.keys(STUDY_PHASE_LABELS));
  });

  it("has non-empty copy for every known run error code", () => {
    for (const [code, message] of Object.entries(RUN_ERROR_MESSAGES)) {
      expect(message.trim(), code).not.toBe("");
    }
  });

  it("names the unconfigured analysis service", () => {
    expect(formatStudyRunError({ code: "not_configured" })).toBe(
      "The analysis service is not configured.",
    );
  });

  it("falls back for an unknown wire error code", () => {
    expect(
      formatStudyRunError({
        code: "not_a_real_code",
      } as unknown as StudyRunError),
    ).toBe("The study request failed.");
  });
});
