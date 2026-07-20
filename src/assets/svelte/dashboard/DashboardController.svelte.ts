import { CanvasDocument } from "./canvas/CanvasDocument.svelte";
import { SimulationReportDocument } from "./simulation/SimulationReportDocument.svelte";
import type {
  WorkspaceDocument,
  DocumentKind,
} from "./workspace/WorkspaceDocument.svelte";
import { createDocument } from "./workspace/WorkspaceDocument.svelte";
import type { LoadedGraph } from "./contract";

export class DashboardController {
  private _documents = $state<WorkspaceDocument[]>([]);
  public selectedDocumentId = $state<string | undefined>();

  get documents(): WorkspaceDocument[] {
    return this._documents;
  }

  get activeDocument(): WorkspaceDocument | undefined {
    return this._documents.find((each) => each.id === this.selectedDocumentId);
  }

  get activeCanvas(): CanvasDocument | undefined {
    const doc = this.activeDocument;
    if (doc?.kind === "canvas") return doc as CanvasDocument;
    return undefined;
  }

  get hasUnreadReport(): boolean {
    return this._documents.some(
      (d) =>
        d.kind === "simulation-report" &&
        (d as SimulationReportDocument).hasUnread,
    );
  }

  createDocument(kind: DocumentKind): void {
    if (kind === "canvas") {
      const canvas = createDocument(
        "canvas",
        "Untitled canvas",
      ) as CanvasDocument;
      this._documents.push(canvas);
      this.selectedDocumentId = canvas.id;
    }
  }

  openLoadedGraph(graph: LoadedGraph): CanvasDocument | undefined {
    const existing = this._documents.find(
      (d) =>
        d.kind === "canvas" && (d as CanvasDocument).loadedGraphId === graph.id,
    );
    if (existing) {
      this.selectedDocumentId = existing.id;
      return undefined;
    }

    const blankCanvas = this._documents.find(
      (d) => d.kind === "canvas" && !(d as CanvasDocument).loaded,
    );

    if (blankCanvas) {
      (blankCanvas as CanvasDocument).replaceFromLoadedGraph(graph);
      this.selectedDocumentId = blankCanvas.id;
      return blankCanvas as CanvasDocument;
    }

    const canvas = createDocument("canvas", graph.title) as CanvasDocument;
    canvas.replaceFromLoadedGraph(graph);
    this._documents.push(canvas);
    this.selectedDocumentId = canvas.id;
    return canvas;
  }

  runSimulationForGraph(graphId: string, graphTitle: string): void {
    const existing = this._documents.find(
      (d) =>
        d.kind === "simulation-report" &&
        (d as SimulationReportDocument).graphId === graphId,
    ) as SimulationReportDocument | undefined;

    if (existing) {
      existing.markWaiting();
      this.selectedDocumentId = existing.id;
    } else {
      const report = createDocument(
        "simulation-report",
        graphTitle,
        graphId,
      ) as SimulationReportDocument;
      report.markWaiting();
      this._documents.push(report);
      this.selectedDocumentId = report.id;
    }
  }

  showSimulationReport(
    runs: { id: string; graph_id: string; graph_title: string }[],
  ): void {
    if (runs.length === 0) return;
    const run = runs[0];
    const existing = this._documents.find(
      (d) =>
        d.kind === "simulation-report" &&
        (d as SimulationReportDocument).graphId === run.graph_id,
    ) as SimulationReportDocument | undefined;

    if (existing) {
      this.selectedDocumentId = existing.id;
    }
  }

  selectDocument(id: string): void {
    this.selectedDocumentId = id;

    const doc = this.activeDocument;
    if (doc?.kind === "simulation-report") {
      const report = doc as SimulationReportDocument;
      report.markRead();
    }
  }

  isCanvasDocumentSelected(): boolean {
    return this.activeDocument?.kind === "canvas";
  }

  isSimulationDocumentSelected(): boolean {
    return this.activeDocument?.kind === "simulation-report";
  }

  closeDocument(id: string): void {
    const currentIdx = this._documents.findIndex((d) => d.id === id);
    if (currentIdx === -1) return;

    this._documents = this._documents.filter((d) => d.id !== id);

    if (this.selectedDocumentId === id) {
      if (this._documents.length === 0) {
        this.selectedDocumentId = undefined;
      } else {
        const nextIdx = currentIdx > 0 ? currentIdx - 1 : 0;
        this.selectedDocumentId = this._documents[nextIdx]?.id;
      }
    }
  }

  onSimulationDone(payload: {
    id: string;
    graph_id: string;
    message: string;
  }): SimulationReportDocument | null {
    const report = this._documents.find(
      (d) =>
        d.kind === "simulation-report" &&
        (d as SimulationReportDocument).graphId === payload.graph_id,
    ) as SimulationReportDocument | undefined;

    if (!report) return null;

    report.markReady(payload.id);

    if (report.id === this.selectedDocumentId) {
      return report;
    }

    report.hasUnread = true;
    return null;
  }

  getReportDocumentForCanvas(
    canvas: CanvasDocument,
  ): SimulationReportDocument | undefined {
    return this._documents.find(
      (d) =>
        d.kind === "simulation-report" &&
        (d as SimulationReportDocument).graphId === canvas.loadedGraphId,
    ) as SimulationReportDocument | undefined;
  }
}
