import type { Component } from "svelte";
import type { WorkspaceDocument } from "./WorkspaceDocument.svelte";
import type { DashboardApi } from "../dashboard-api";
import EditableCanvas from "../graph/canvas/EditableCanvas.svelte";
import GraphDiff from "../graph/GraphDiff.svelte";
import SimulationReport from "../simulation-report/SimulationReport.svelte";
import OptimizationReport from "../optimization-report/OptimizationReport.svelte";
import ComparisonReport from "../comparison-report/ComparisonReport.svelte";
import AnalysisReport from "../analysis-report/AnalysisReport.svelte";
import DocumentCatalog from "../document-catalog/DocumentCatalog.svelte";

export interface DocumentRegistry<
  D extends WorkspaceDocument = WorkspaceDocument,
  Api = DashboardApi,
> {
  readonly views: Record<string, Component<{ document: D; api: Api }>>;
  create(kind: string): D | undefined;
}

export const dashboardRegistry: DocumentRegistry = {
  views: {
    graph: EditableCanvas as unknown as Component<{
      document: WorkspaceDocument;
      api: DashboardApi;
    }>,
    "graph-diff": GraphDiff as unknown as Component<{
      document: WorkspaceDocument;
      api: DashboardApi;
    }>,
    "simulation-report": SimulationReport as unknown as Component<{
      document: WorkspaceDocument;
      api: DashboardApi;
    }>,
    "optimization-report": OptimizationReport as unknown as Component<{
      document: WorkspaceDocument;
      api: DashboardApi;
    }>,
    "comparison-report": ComparisonReport as unknown as Component<{
      document: WorkspaceDocument;
      api: DashboardApi;
    }>,
    "analysis-report": AnalysisReport as unknown as Component<{
      document: WorkspaceDocument;
      api: DashboardApi;
    }>,
    "document-catalog": DocumentCatalog as unknown as Component<{
      document: WorkspaceDocument;
      api: DashboardApi;
    }>,
  },
  create(_kind: string) {
    // Document creation is handled by WorkspaceModel (topologyPicker / openDocumentCatalog).
    // Kept for registry interface completeness; not used for polymorphic content dispatch.
    return undefined;
  },
};
