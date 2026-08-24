import { WorkspaceDocumentBase } from "../workspace/WorkspaceDocument.svelte";
import type { DashboardRecoveryContext } from "../workspace/recovery-context";
import type { PersistedWorkspaceDocument } from "../../ui-kit/workspace/workspace-persistence";
import type { DocumentCatalogItem } from "../contract";

export type CatalogItemOpener = (
  item: DocumentCatalogItem,
) => Promise<boolean> | boolean;

export class DocumentCatalogDocument extends WorkspaceDocumentBase {
  static readonly relationNodePrefix = "catalog-related:";
  static readonly kindLabels: Readonly<Record<string, string>> = {
    graph: "Graph",
    simulation_report: "Simulation report",
    optimization_report: "Optimization report",
    analysis_report: "Analysis report",
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
  chosenKeys = $state.raw<string[]>([]);
  knownItems = $state.raw<Map<string, DocumentCatalogItem>>(new Map());
  relatedGraphIds = $state.raw<string[]>([]);
  relatedItems = $state.raw<DocumentCatalogItem[]>([]);

  constructor(opener?: CatalogItemOpener) {
    super();
    if (opener) this.opener = opener;
  }

  openItem(item: DocumentCatalogItem): Promise<boolean> | boolean {
    return this.opener(item);
  }

  get chosenItems(): DocumentCatalogItem[] {
    return this.chosenKeys.flatMap((key) => {
      const item = this.knownItems.get(key);
      return item ? [item] : [];
    });
  }

  get showingRelated(): boolean {
    return this.relatedGraphIds.length > 0;
  }

  setChosenKeys(keys: string[]): void {
    this.chosenKeys = [...new Set(keys)];
  }

  toggleChosen(key: string): void {
    this.chosenKeys = this.chosenKeys.includes(key)
      ? this.chosenKeys.filter((chosenKey) => chosenKey !== key)
      : [...this.chosenKeys, key];
  }

  rememberItems(
    items: readonly DocumentCatalogItem[],
    relatedItems: readonly DocumentCatalogItem[],
  ): void {
    this.knownItems = new Map([
      ...this.knownItems,
      ...items.map((item) => [item.id, item] as const),
      ...relatedItems.map((item) => [item.id, item] as const),
    ]);
    this.relatedItems = [...relatedItems];
  }

  showRelated(): boolean {
    const graphIds = this.chosenItems.map((item) => item.graph_id);
    this.relatedGraphIds = [...new Set(graphIds)];
    return this.relatedGraphIds.length > 0;
  }

  hideRelated(): void {
    this.relatedGraphIds = [];
    this.relatedItems = [];
  }

  relationItem(nodeId: string): DocumentCatalogItem | undefined {
    return this.relatedItems.find(
      (item) => DocumentCatalogDocument.relationNodeId(item) === nodeId,
    );
  }

  static relationNodeId(item: DocumentCatalogItem): string {
    return `${this.relationNodePrefix}${item.kind}:${item.id}`;
  }

  static relationIcon(item: DocumentCatalogItem): string {
    switch (item.kind) {
      case "graph":
        return "graph";
      case "simulation_report":
        return "simulation-report";
      case "optimization_report":
        return "shield";
      case "analysis_report":
        return "simulation-report";
    }
  }

  static relationLabel(item: DocumentCatalogItem): string {
    if (item.kind === "graph") {
      return `${item.graph_title} · ${item.revision_kind} #${item.revision_number}`;
    }
    return `${this.kindLabel(item.kind)} · ${item.revision_kind} #${item.revision_number}`;
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
