import type { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import type { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import type { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
import type { ComparisonReportDocument } from "../comparison-report/ComparisonReportDocument.svelte";
import type { DocumentCatalogDocument } from "../document-catalog/DocumentCatalogDocument.svelte";
import type { ReportDataMap, ReportKind } from "../report-events";
import type { DashboardError } from "../contract";
import { UiWorkspaceDocument } from "../../ui-kit/workspace/WorkspaceDocument.svelte";

// ponytail: extends kit UiWorkspaceDocument - domain fields stay here per Option A.
// This concrete base stays app-side: it adds AsyncReportDocument + report accessors the kit does not have.
export abstract class WorkspaceDocumentBase extends UiWorkspaceDocument {
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

  status = $state<
    "pending" | "ready" | "loading" | "loaded" | "error" | "completed"
  >("pending");
  progress = $state<{
    completed: number;
    total: number;
    detail?: string;
  } | null>(null);

  abstract get reportId(): string | null;

  abstract get reportApiKind(): "simulation_report" | "optimization_report";

  abstract setReportData(data: ReportDataMap[Kind]): void;

  abstract markError(error: DashboardError): void;

  setProgress(completed: number, total: number, detail?: string): void {
    if (this.status !== "pending") return;
    this.progress = { completed, total, ...(detail ? { detail } : {}) };
  }
}

export type WorkspaceDocument =
  | EditableGraphDocument
  | GraphDiffDocument
  | SimulationReportDocument
  | OptimizationReportDocument
  | ComparisonReportDocument
  | DocumentCatalogDocument;

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
