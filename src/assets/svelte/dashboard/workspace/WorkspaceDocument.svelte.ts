import type { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import type { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import type { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
import type { ComparisonReportDocument } from "../comparison-report/ComparisonReportDocument.svelte";
import type { ClientReportEvent, EventResult } from "../report-events";

export class WorkspaceDocumentBase {
  isReportDocument(): boolean {
    return false;
  }

  isAsyncReportDocument(): this is AsyncReportDocument {
    return false;
  }
}

export abstract class AsyncReportDocument extends WorkspaceDocumentBase {
  isReportDocument(): true {
    return true;
  }

  isAsyncReportDocument(): this is AsyncReportDocument {
    return true;
  }

  abstract accept(event: ClientReportEvent): EventResult;
}

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
  return document.isReportDocument();
}

export function isGraphDiff(
  document: WorkspaceDocument,
): document is GraphDiffDocument {
  return document.kind === "graph-diff";
}
