import type { CanvasDocument } from "./CanvasDocument.svelte";
import type { SimulationReportDocument } from "./SimulationReportDocument.svelte";

export type DocumentKind = "canvas" | "simulation-report";

export interface DocumentBase {
  readonly id: string;
  readonly kind: DocumentKind;
  readonly title: string;
}

export type WorkspaceDocument = CanvasDocument | SimulationReportDocument;
