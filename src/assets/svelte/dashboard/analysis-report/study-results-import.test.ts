import { describe, expect, it } from "vitest";
import {
  MAX_STUDY_RESULTS_ARCHIVE_BYTES,
  readStudyResultsArchive,
} from "./study-results-import";

describe("readStudyResultsArchive", () => {
  it("does not encode an empty selection", async () => {
    await expect(readStudyResultsArchive(undefined)).resolves.toEqual({
      status: "empty",
    });
  });

  it("rejects oversized files before reading bytes", async () => {
    const file = {
      size: MAX_STUDY_RESULTS_ARCHIVE_BYTES + 1,
      arrayBuffer: () => {
        throw new Error("must not read oversized files");
      },
    } as unknown as File;

    await expect(readStudyResultsArchive(file)).resolves.toEqual({
      status: "too_large",
    });
  });

  it("encodes archive bytes with bounded chunks", async () => {
    const file = {
      size: 3,
      arrayBuffer: async () => new Uint8Array([0, 255, 16]).buffer,
    } as unknown as File;

    await expect(readStudyResultsArchive(file)).resolves.toEqual({
      status: "ok",
      archive: "AP8Q",
    });
  });
});
