import type { Component } from "svelte";
import type { WorkspaceDocument } from "./WorkspaceDocument.svelte";
import type { DashboardApi } from "../dashboard-api";
import type { DashboardRecoveryContext } from "./recovery-context";
import type { WorkspaceModel } from "./WorkspaceModel.svelte";
import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import { OptimizationReportDocument } from "../optimization-report/OptimizationReportDocument.svelte";
import { AnalysisReportDocument } from "../analysis-report/AnalysisReportDocument.svelte";
import { DocumentCatalogDocument } from "../document-catalog/DocumentCatalogDocument.svelte";
import { RunsDocument } from "../runs/RunsDocument.svelte";
import EditableCanvas from "../graph/canvas/EditableCanvas.svelte";
import GraphDiff from "../graph/GraphDiff.svelte";
import SimulationReport from "../simulation-report/SimulationReport.svelte";
import OptimizationReport from "../optimization-report/OptimizationReport.svelte";
import AnalysisReport from "../analysis-report/AnalysisReport.svelte";
import DocumentCatalog from "../document-catalog/DocumentCatalog.svelte";
import Runs from "../runs/Runs.svelte";

export interface DashboardDocumentRegistration {
  view: Component<{
    document: WorkspaceDocument;
    api: DashboardApi;
    onCancel?: () => Promise<boolean>;
  }>;
  fromPersisted?: (
    data: unknown,
    context: DashboardRecoveryContext,
  ) => WorkspaceDocument | undefined;
  createOption?: { id: string; label: string; icon?: string };
  create?(workspace: WorkspaceModel): void;
}

export const dashboardRegistry: Record<string, DashboardDocumentRegistration> =
  {
    graph: {
      view: EditableCanvas as unknown as DashboardDocumentRegistration["view"],
      fromPersisted: EditableGraphDocument.fromPersisted,
      createOption: EditableGraphDocument.createOption,
      create: (workspace) => {
        workspace.topologyPickerOpen = true;
        workspace.topologyPickerStatus = "";
      },
    },
    "graph-diff": {
      view: GraphDiff as unknown as DashboardDocumentRegistration["view"],
      fromPersisted: GraphDiffDocument.fromPersisted,
    },
    "simulation-report": {
      view: SimulationReport as unknown as DashboardDocumentRegistration["view"],
      fromPersisted: SimulationReportDocument.fromPersisted,
    },
    "optimization-report": {
      view: OptimizationReport as unknown as DashboardDocumentRegistration["view"],
      fromPersisted: OptimizationReportDocument.fromPersisted,
    },
    "analysis-report": {
      view: AnalysisReport as unknown as DashboardDocumentRegistration["view"],
      fromPersisted: AnalysisReportDocument.fromPersisted,
    },
    "document-catalog": {
      view: DocumentCatalog as unknown as DashboardDocumentRegistration["view"],
      fromPersisted: DocumentCatalogDocument.fromPersisted,
      createOption: DocumentCatalogDocument.createOption,
      create: (workspace) => workspace.openDocumentCatalog(),
    },
    runs: {
      view: Runs as unknown as DashboardDocumentRegistration["view"],
      fromPersisted: RunsDocument.fromPersisted,
      createOption: RunsDocument.createOption,
      create: (workspace) => workspace.openRuns(),
    },
  };
