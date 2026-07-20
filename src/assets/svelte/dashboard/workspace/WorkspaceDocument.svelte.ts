import type { ComponentType } from "svelte";
import type { CanvasDocument } from "../canvas/CanvasDocument.svelte";
import type { SimulationReportDocument } from "../simulation/SimulationReportDocument.svelte";

export type DocumentKind = "canvas" | "simulation-report";

export interface DocumentBase {
  readonly id: string;
  readonly kind: DocumentKind;
  readonly title: string;
}

export type WorkspaceDocument = CanvasDocument | SimulationReportDocument;

type DocumentCtor = (...args: any[]) => WorkspaceDocument;

const ctorRegistry: Record<string, DocumentCtor> = {};
const rendererRegistry: Record<string, ComponentType> = {};

export function registerDocument(kind: DocumentKind, ctor: DocumentCtor): void {
  ctorRegistry[kind] = ctor;
}

export function registerRenderer(
  kind: DocumentKind,
  component: ComponentType,
): void {
  rendererRegistry[kind] = component;
}

export function createDocument(
  kind: DocumentKind,
  ...args: any[]
): WorkspaceDocument {
  const ctor = ctorRegistry[kind];
  if (!ctor) throw new Error(`Unknown document kind: ${kind}`);
  return ctor(...args);
}

export function getRenderer(kind: DocumentKind): ComponentType | undefined {
  return rendererRegistry[kind];
}
