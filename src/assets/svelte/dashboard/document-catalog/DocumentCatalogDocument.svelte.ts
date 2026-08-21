import { WorkspaceDocumentBase } from "../workspace/WorkspaceDocument.svelte";
import type { DashboardRecoveryContext } from "../workspace/recovery-context";
import type { PersistedWorkspaceDocument } from "../../ui-kit/workspace/workspace-persistence";
import type { DocumentCatalogItem } from "../contract";

export type CatalogItemOpener = (
  item: DocumentCatalogItem,
) => Promise<boolean> | boolean;

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
  readonly icon = "squares-2x2" as const satisfies string;
  static readonly createOption = {
    id: "document-catalog",
    label: "Documents",
    icon: "squares-2x2" as const,
  };

  private opener: CatalogItemOpener = () => false;

  constructor(opener?: CatalogItemOpener) {
    super();
    if (opener) this.opener = opener;
  }

  openItem(item: DocumentCatalogItem): Promise<boolean> | boolean {
    return this.opener(item);
  }

  static kindLabel(kind: string): string {
    return this.kindLabels[kind] ?? this.kindLabels.graph;
  }

  static fromPersisted(
    _data: unknown,
    context: DashboardRecoveryContext,
  ): DocumentCatalogDocument {
    return new DocumentCatalogDocument((item) =>
      context.workspace.openCatalogItem(context.api, item),
    );
  }

  toPersisted(): PersistedWorkspaceDocument | undefined {
    return { kind: "document-catalog", ids: {}, title: this.title };
  }
}
