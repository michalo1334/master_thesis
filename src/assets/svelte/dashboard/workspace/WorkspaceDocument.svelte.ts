import type { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import type { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import type { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
import type { ComparisonReportDocument } from "../comparison-report/ComparisonReportDocument.svelte";
import type { ReportDataMap, ReportKind } from "../report-events";
import type { DashboardError } from "../contract";

export class WorkspaceDocumentBase {
  isReportDocument(): boolean {
    return false;
  }

  isAsyncReportDocument(): this is AsyncReportDocument<ReportKind> {
    return false;
  }
}

export abstract class AsyncReportDocument<
  Kind extends ReportKind,
> extends WorkspaceDocumentBase {
  abstract readonly reportKind: Kind;

  isReportDocument(): true {
    return true;
  }

  isAsyncReportDocument(): this is AsyncReportDocument<Kind> {
    return true;
  }

  abstract setReportData(data: ReportDataMap[Kind]): void;

  abstract markError(error: DashboardError): void;
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
