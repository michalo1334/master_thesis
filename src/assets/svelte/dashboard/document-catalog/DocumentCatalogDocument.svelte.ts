import type { IconName } from "../types";
import { WorkspaceDocumentBase } from "../workspace/WorkspaceDocument.svelte";

export class DocumentCatalogDocument extends WorkspaceDocumentBase {
  static readonly kindLabels: Readonly<Record<string, string>> = {
    graph: "Graph",
    simulation_report: "Simulation report",
    optimization_report: "Optimization report",
  };

  readonly kind = "document-catalog" as const;
  readonly documentLabel = "Table";
  readonly id = "document-catalog";
  readonly title = "Documents";
  readonly icon = "squares-2x2" as const satisfies IconName;
  static readonly createOption = {
    id: "document-catalog",
    label: "Documents",
    icon: "squares-2x2" as const,
  };

  static kindLabel(kind: string): string {
    return this.kindLabels[kind] ?? this.kindLabels.graph;
  }
}
