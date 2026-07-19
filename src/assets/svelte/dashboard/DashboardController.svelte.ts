import { CanvasDocument } from "./workspace/CanvasDocument.svelte";
import { SimulationReportDocument } from "./simulation/SimulationReportDocument.svelte";
import type {
  WorkspaceDocument,
  DocumentKind,
} from "./workspace/WorkspaceDocument.svelte";
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

  createDocument(kind: DocumentKind): void {
    if (kind === "canvas") {
      const canvas = new CanvasDocument("Untitled canvas");
      this._documents.push(canvas);
      this.selectedDocumentId = canvas.id;
    } else {
      const report = new SimulationReportDocument("Simulation report");
      this._documents.push(report);
      this.selectedDocumentId = report.id;
    }
  }

  /**
   * Open a loaded graph from the server.
   * Returns the CanvasDocument if a new tab was created,
   * or undefined if an existing tab was activated (dedup).
   */
  openLoadedGraph(graph: LoadedGraph): CanvasDocument | undefined {
    // Dedup: if this loaded graph is already open, activate it.
    const existing = this._documents.find(
      (d) =>
        d.kind === "canvas" && (d as CanvasDocument).loadedGraphId === graph.id,
    );
    if (existing) {
      this.selectedDocumentId = existing.id;
      return undefined;
    }

    // Reuse the first blank canvas, or create a new tab.
    const blankCanvas = this._documents.find(
      (d) => d.kind === "canvas" && !(d as CanvasDocument).loaded,
    );

    if (blankCanvas) {
      (blankCanvas as CanvasDocument).replaceFromLoadedGraph(graph);
      this.selectedDocumentId = blankCanvas.id;
      return blankCanvas as CanvasDocument;
    }

    const canvas = new CanvasDocument(graph.title);
    canvas.replaceFromLoadedGraph(graph);
    this._documents.push(canvas);
    this.selectedDocumentId = canvas.id;
    return canvas;
  }

  selectDocument(id: string): void {
    this.selectedDocumentId = id;
  }

  isCanvasDocumentSelected() : boolean {
    return this.activeDocument?.kind === "canvas";
  }

  isSimulationDocumentSelected() : boolean {
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

  runSimulation(id: string): void {

  }
}
