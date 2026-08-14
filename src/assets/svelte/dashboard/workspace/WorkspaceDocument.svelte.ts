import type { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import type { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import type { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
import type { ComparisonReportDocument } from "../comparison-report/ComparisonReportDocument.svelte";

export type WorkspaceDocument =
  | EditableGraphDocument
  | GraphDiffDocument
  | SimulationReportDocument
  | OptimizationReportDocument
  | ComparisonReportDocument;

export function isReport(
  document: WorkspaceDocument,
): document is
  | SimulationReportDocument
  | OptimizationReportDocument
  | ComparisonReportDocument {
  return (
    document.kind === "simulation-report" ||
    document.kind === "optimization-report" ||
    document.kind === "comparison-report"
  );
}

export function isGraphDiff(
  document: WorkspaceDocument,
): document is GraphDiffDocument {
  return document.kind === "graph-diff";
}
