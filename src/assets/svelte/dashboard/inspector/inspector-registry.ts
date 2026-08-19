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
 * edgeRegistry → inspectorFor). Document-level inspectors are a separate
 * axis (graph vs report). Keeping both here makes DashboardInspector
 * registry-driven and allows the kit to import InspectorRegistry
 * types without knowing Selectable / contract types (string keys).
 */
export interface InspectorRegistry {
  readonly selectableInspectors: {
    forSelectable(selectable: Selectable | undefined): Component<any>;
  };
  readonly documentInspectors: {
    readonly graph: typeof GraphInspector;
    readonly report: typeof ReportInspector;
  };
}

export const inspectorRegistry: InspectorRegistry = {
  selectableInspectors: {
    forSelectable: selectableInspectorFor,
  },
  documentInspectors: {
    graph: GraphInspector,
    report: ReportInspector,
  },
};

// Re-export for kit extraction.
export type { NodePresentation, EdgePresentation };
export { EmptyInspector };
