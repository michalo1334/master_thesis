import { buildRows, type OutlineRow } from "./document-outline";

/**
 * App-specific builder: maps domain (documents + folders + graphSummaries)
 * to generic outline rows. Kit's DocumentOutline will take OutlineRow[].
 */
export { buildRows as buildDashboardRows, type OutlineRow };
