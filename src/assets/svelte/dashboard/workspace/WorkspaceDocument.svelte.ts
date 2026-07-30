import type { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import type { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";

export type WorkspaceDocument =
  EditableGraphDocument | SimulationReportDocument | OptimizationReportDocument;

export function isReport(
  document: WorkspaceDocument,
): document is SimulationReportDocument | OptimizationReportDocument {
  return (
    document.kind === "simulation-report" ||
    document.kind === "optimization-report"
  );
}
