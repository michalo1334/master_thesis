import type { Component } from "svelte";
import type { UiWorkspaceDocument } from "./WorkspaceDocument.svelte";

export interface InspectorContext {
  graph?: unknown;
  api?: unknown;
  revisionId?: string | null;
  canEditFlows?: boolean;
  onUpdate?: (...args: unknown[]) => unknown;
}

export interface InspectorRegistry<
  Doc extends UiWorkspaceDocument,
  Sel extends { type: string },
> {
  readonly documentInspectors: Record<string, Component<{ document: Doc }>>;
  readonly selectableInspectors: Record<
    string,
    Component<{ selectable: Sel; context?: InspectorContext }>
  >;
  readonly fallback: Component;
}
