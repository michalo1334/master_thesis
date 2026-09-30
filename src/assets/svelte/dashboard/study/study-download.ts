import type { StudyMode } from "./study-types";

/**
 * Delay before the object URL is revoked.
 *
 * The browser starts the download asynchronously after the synthetic click, so
 * revoking the URL in the same task can cancel a slow start. The delay keeps
 * the URL alive long enough for the download to begin, then releases it.
 */
export const DOWNLOAD_REVOKE_DELAY_MS = 1_000;

/**
 * Requests one browser download of the exact result ZIP bytes.
 *
 * `archive` is the base64 the server delivered. The bytes are decoded before
 * any Blob or object URL exists, so invalid base64 reports `false` without
 * starting a download or marking the result as requested. The decoded bytes
 * stay byte-for-byte identical to the validated ZIP, including arbitrary
 * binary values.
 *
 * Returns `true` only when the download was requested.
 */
export function downloadStudyResult(
  archive: string,
  filename: string,
): boolean {
  const bytes = decodeBase64(archive);
  if (bytes === null) return false;

  const url = URL.createObjectURL(
    new Blob([bytes as BlobPart], { type: "application/zip" }),
  );
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  globalThis.setTimeout(
    () => URL.revokeObjectURL(url),
    DOWNLOAD_REVOKE_DELAY_MS,
  );
  return true;
}

/**
 * Builds a safe download filename from untrusted study metadata.
 *
 * The study identifier crosses the wire, so every character outside a small
 * safe set becomes a separator. The specification version pins the exact
 * immutable inputs that produced the result, so two versions never share one
 * filename. A missing or invalid version is omitted.
 */
export function studyResultFilename(
  studyId: string,
  specificationVersion: number | null,
  mode: StudyMode,
): string {
  const safe = studyId
    .replace(/[^A-Za-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "");
  const version =
    typeof specificationVersion === "number" &&
    Number.isInteger(specificationVersion) &&
    specificationVersion > 0
      ? `-v${specificationVersion}`
      : "";
  return `${safe === "" ? "study" : safe}${version}-${mode}.zip`;
}

/**
 * Decodes base64 into the exact bytes, or `null` for invalid input.
 *
 * `atob` rejects invalid characters and a truncated length, so a corrupted
 * wire value never reaches a Blob.
 */
function decodeBase64(archive: string): Uint8Array | null {
  let binary: string;
  try {
    binary = atob(archive);
  } catch {
    return null;
  }

  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  return bytes;
}
