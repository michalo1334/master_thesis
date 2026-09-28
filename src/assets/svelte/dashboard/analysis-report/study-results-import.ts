export const MAX_STUDY_RESULTS_ARCHIVE_BYTES = 50 * 1024 * 1024;

type ArchiveReadResult =
  { status: "ok"; archive: string } | { status: "empty" | "too_large" };

export async function readStudyResultsArchive(
  file: File | undefined,
  maxBytes = MAX_STUDY_RESULTS_ARCHIVE_BYTES,
): Promise<ArchiveReadResult> {
  if (!file || file.size === 0) return { status: "empty" };
  if (file.size > maxBytes) return { status: "too_large" };

  return {
    status: "ok",
    archive: bytesToBase64(new Uint8Array(await file.arrayBuffer())),
  };
}

function bytesToBase64(bytes: Uint8Array): string {
  const chunkSize = 0x8000;
  let binary = "";

  for (let start = 0; start < bytes.length; start += chunkSize) {
    const end = Math.min(start + chunkSize, bytes.length);
    for (let index = start; index < end; index += 1) {
      binary += String.fromCharCode(bytes[index]!);
    }
  }

  return btoa(binary);
}
