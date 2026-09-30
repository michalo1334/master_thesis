import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  DOWNLOAD_REVOKE_DELAY_MS,
  downloadStudyResult,
  studyResultFilename,
} from "./study-download";

/** Builds base64 for the exact bytes, including values above 0x7f. */
function base64Of(bytes: readonly number[]): string {
  return btoa(String.fromCharCode(...bytes));
}

describe("studyResultFilename", () => {
  it("keeps a safe study identifier, the specification version, and the mode", () => {
    expect(studyResultFilename("topology-scale-study", 3, "final")).toBe(
      "topology-scale-study-v3-final.zip",
    );
  });

  it("keeps two specification versions apart", () => {
    expect(studyResultFilename("topology-scale-study", 1, "pilot")).not.toBe(
      studyResultFilename("topology-scale-study", 2, "pilot"),
    );
  });

  it("replaces unsafe characters from untrusted metadata", () => {
    expect(studyResultFilename("study one/../evil", 2, "pilot")).toBe(
      "study-one-..-evil-v2-pilot.zip",
    );
  });

  it("falls back when no safe character remains", () => {
    expect(studyResultFilename("///", 1, "pilot")).toBe("study-v1-pilot.zip");
  });

  it("omits a missing or invalid version", () => {
    expect(studyResultFilename("study-one", null, "pilot")).toBe(
      "study-one-pilot.zip",
    );
    expect(studyResultFilename("study-one", 0, "pilot")).toBe(
      "study-one-pilot.zip",
    );
  });
});

describe("downloadStudyResult", () => {
  beforeEach(() => {
    Object.defineProperty(URL, "createObjectURL", {
      configurable: true,
      writable: true,
      value: vi.fn(() => "blob:study"),
    });
    Object.defineProperty(URL, "revokeObjectURL", {
      configurable: true,
      writable: true,
      value: vi.fn(),
    });
    vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {});
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it("requests the download with the safe filename", () => {
    const anchors: HTMLAnchorElement[] = [];
    const createElement = document.createElement.bind(document);
    vi.spyOn(document, "createElement").mockImplementation((tag: string) => {
      const element = createElement(tag);
      if (tag === "a") anchors.push(element as HTMLAnchorElement);
      return element;
    });

    expect(
      downloadStudyResult(btoa("exact-archive-bytes"), "study-one-pilot.zip"),
    ).toBe(true);

    expect(anchors[0]?.download).toBe("study-one-pilot.zip");
    expect(anchors[0]?.href).toBe("blob:study");
    expect(HTMLAnchorElement.prototype.click).toHaveBeenCalled();
  });

  it("decodes arbitrary binary bytes byte-for-byte", async () => {
    const bytes = [0x00, 0xff, 0x0a, 0x7f, 0x80, 0x10, 0xc3, 0x28];
    const archive = base64Of(bytes);

    expect(downloadStudyResult(archive, "study-one-final.zip")).toBe(true);

    const blob = vi.mocked(URL.createObjectURL).mock.calls[0]?.[0] as Blob;
    expect(new Uint8Array(await blob.arrayBuffer())).toEqual(
      new Uint8Array(bytes),
    );
  });

  it("reports invalid base64 without starting a download", () => {
    expect(downloadStudyResult("!!not base64!!", "study-one-pilot.zip")).toBe(
      false,
    );
    expect(URL.createObjectURL).not.toHaveBeenCalled();
    expect(HTMLAnchorElement.prototype.click).not.toHaveBeenCalled();
  });

  it("defers the object URL revocation past the click task", () => {
    vi.useFakeTimers();

    expect(downloadStudyResult(btoa("exact"), "study-one-pilot.zip")).toBe(
      true,
    );

    expect(URL.revokeObjectURL).not.toHaveBeenCalled();

    vi.advanceTimersByTime(DOWNLOAD_REVOKE_DELAY_MS);

    expect(URL.revokeObjectURL).toHaveBeenCalledWith("blob:study");
  });
});
