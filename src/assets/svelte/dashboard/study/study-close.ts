import type { DashboardApi } from "../dashboard-api";

/**
 * Requests the server close of one study document and reports the acknowledgment.
 *
 * A `closed` or `not_found` reply means the server holds no task for the
 * document, so the caller can remove the client handle. Any other reply, or a
 * transport failure, leaves cleanup unconfirmed: the caller keeps the handle
 * and surfaces a retryable close error.
 *
 * The caller always names the originally requested document id, so a
 * mismatched start reply cannot cancel a different document.
 */
export async function requestStudyClose(
  api: DashboardApi | undefined,
  documentId: string,
): Promise<boolean> {
  if (!api) return false;
  try {
    const reply = await api.closeStudyDocument({ document_id: documentId });
    return reply.status === "closed" || reply.status === "not_found";
  } catch {
    return false;
  }
}
