import type { Component } from "svelte";
import type { Selectable } from "../contract";
import EmptyInspector from "./EmptyInspector.svelte";
import {
  inspectorFor as selectableInspectorFor,
  type NodePresentation,
  type EdgePresentation,
} from "../graph/presentation/registry";
import GraphInspector from "./graph/GraphInspector.svelte";
import ReportInspector from "./report/ReportInspector.svelte";

/**
 * App-side inspector registry.
 *
 * Selectable inspectors reuse the presentation registry (nodeRegistry +
 * edgeRegistry → inspectorFor). Document-level inspectors are keyed by
 * document kind (graph / simulation-report / optimization-report).
 * Keeping both here makes DashboardInspector registry-driven and allows
 * the kit to import InspectorRegistry types without knowing Selectable /
 * contract types (string keys).
 */
export interface InspectorRegistry {
  readonly selectableInspectors: {
    forSelectable(selectable: Selectable | undefined): Component<any>;
  };
  readonly documentInspectors: Readonly<Record<string, Component<any>>>;
  readonly fallback: Component<any>;
}

export const inspectorRegistry: InspectorRegistry = {
  selectableInspectors: {
    forSelectable: selectableInspectorFor,
  },
  documentInspectors: {
    graph: GraphInspector,
    "simulation-report": ReportInspector,
    "optimization-report": ReportInspector,
  },
  fallback: EmptyInspector,
};

export function getDocumentInspector(kind: string): Component<any> {
  return (
    inspectorRegistry.documentInspectors[kind] ?? inspectorRegistry.fallback
  );
}

// Re-export for kit extraction.
export type { NodePresentation, EdgePresentation };
export { EmptyInspector };
