<script lang="ts">
  import Icon from "../ui/Icon.svelte";
  import { isReport, type WorkspaceDocument } from "./WorkspaceDocument.svelte";
  import { SvelteMap, SvelteSet } from "svelte/reactivity";

  interface DocumentOutlineRow {
    type: "document";
    document: WorkspaceDocument;
    depth: number;
  }

  type OutlineRow = DocumentOutlineRow | { type: "reports" };

  interface Props {
    documents: readonly WorkspaceDocument[];
    selectedDocumentId?: string;
    onSelectDocument: (id: string) => void;
    collapsed: boolean;
    onCollapsedChange: (collapsed: boolean) => void;
  }

  let {
    documents,
    selectedDocumentId,
    onSelectDocument,
    collapsed,
    onCollapsedChange,
  }: Props = $props();

  let rows = $derived.by(() => buildRows(documents));

  function buildRows(documents: readonly WorkspaceDocument[]): OutlineRow[] {
    const graphsByLoadedId = new SvelteMap<string, WorkspaceDocument>();

    for (const document of documents) {
      if (document.kind === "graph" && document.loadedGraphId) {
        graphsByLoadedId.set(document.loadedGraphId, document);
      }
    }

    const children = new SvelteMap<string, WorkspaceDocument[]>();
    const roots: WorkspaceDocument[] = [];
    const fallbackReports: WorkspaceDocument[] = [];

    for (const document of documents) {
      const parent = parentDocument(document, graphsByLoadedId);
      if (parent) {
        const siblings = children.get(parent.id) ?? [];
        siblings.push(document);
        children.set(parent.id, siblings);
      } else if (isReport(document)) {
        fallbackReports.push(document);
      } else {
        roots.push(document);
      }
    }

    const rows: OutlineRow[] = [];
    const visit = (
      items: readonly WorkspaceDocument[],
      depth: number,
    ): void => {
      for (const document of items) {
        rows.push({ type: "document", document, depth });
        visit(children.get(document.id) ?? [], depth + 1);
      }
    };

    visit(roots, 0);
    if (fallbackReports.length) {
      rows.push({ type: "reports" });
      visit(fallbackReports, 1);
    }
    return rows;
  }

  function parentDocument(
    document: WorkspaceDocument,
    graphsByLoadedId: ReadonlyMap<string, WorkspaceDocument>,
  ): WorkspaceDocument | undefined {
    if (isReport(document)) {
      return graphsByLoadedId.get(document.graphId);
    }

    if (!document.loadedGraphId || !document.graph.parent_id) return undefined;

    const parent = graphsByLoadedId.get(document.graph.parent_id);
    if (!parent || parent.id === document.id) return undefined;

    // A malformed parent chain is shown at the root instead of recursing forever.
    const visited = new SvelteSet([document.id]);
    let current: WorkspaceDocument | undefined = parent;
    while (current) {
      if (visited.has(current.id)) return undefined;
      visited.add(current.id);
      current =
        current.kind === "graph" && current.graph.parent_id
          ? graphsByLoadedId.get(current.graph.parent_id)
          : undefined;
    }

    return parent;
  }

  function documentType(document: WorkspaceDocument): "Graph" | "Report" {
    return document.kind === "graph" ? "Graph" : "Report";
  }
</script>

<nav class={["document-outline", { collapsed }]} aria-label="Document outline">
  <button
    type="button"
    class="document-outline-toggle"
    aria-label={collapsed
      ? "Expand document outline"
      : "Collapse document outline"}
    aria-expanded={!collapsed}
    onclick={() => onCollapsedChange(!collapsed)}
  >
    <Icon name={collapsed ? "chevron-right" : "chevron-down"} size={18} />
  </button>

  {#if !collapsed}
    <ul>
      {#each rows as row (row.type === "reports" ? "reports" : row.document.id)}
        {#if row.type === "reports"}
          <li class="document-outline-group">
            <span role="heading" aria-level="2">Reports</span>
          </li>
        {:else}
          <li data-depth={row.depth} style:--depth={row.depth}>
            <button
              type="button"
              aria-label={`${documentType(row.document)} ${row.document.title}`}
              aria-current={row.document.id === selectedDocumentId
                ? "page"
                : undefined}
              class={[
                "document-outline-row",
                { current: row.document.id === selectedDocumentId },
              ]}
              onclick={() => onSelectDocument(row.document.id)}
            >
              <Icon
                name={row.document.kind === "graph" ? "graph" : "shield"}
                size={16}
              />
              <span class="document-outline-label">{row.document.title}</span>
            </button>
          </li>
        {/if}
      {/each}
    </ul>
  {/if}
</nav>

<style>
  .document-outline {
    display: none;
  }

  @media (min-width: 75em) {
    .document-outline {
      min-width: 0;
      display: flex;
      flex-direction: column;
      gap: var(--ds-space-2);
      overflow: auto;
      padding: var(--ds-space-3) var(--ds-space-2);
      border-right: 1px solid var(--ds-color-border);
      background: var(--ds-color-border-soft);
    }

    .document-outline.collapsed {
      align-items: center;
      padding: var(--ds-space-2);
      overflow: hidden;
    }

    .document-outline-toggle {
      width: var(--ds-control-height);
      min-height: var(--ds-control-height);
      flex: none;
      border: 0;
      border-radius: var(--ds-radius-sm);
      background: transparent;
      color: var(--ds-color-text-secondary);
      display: grid;
      place-items: center;
    }

    .document-outline-toggle:hover {
      background: var(--ds-color-accent-soft);
      color: var(--ds-color-text);
    }

    .document-outline-toggle:focus-visible {
      outline: 2px solid var(--ds-color-focus);
      outline-offset: -2px;
    }

    ul {
      margin: 0;
      padding: 0;
      min-width: 0;
      list-style: none;
    }

    li {
      --indent-step: 0.875rem;
    }

    .document-outline-group {
      margin-top: var(--ds-space-3);
      padding: 0.375rem var(--ds-space-2);
      color: var(--ds-color-text-secondary);
      font-size: var(--ds-text-sm);
      font-weight: 600;
    }

    .document-outline-row {
      width: 100%;
      min-height: var(--ds-control-height);
      padding: 0.375rem var(--ds-space-2);
      padding-inline-start: calc(
        var(--ds-space-2) + var(--depth, 0) * var(--indent-step)
      );
      border: 0;
      border-radius: var(--ds-radius-sm);
      background: transparent;
      color: var(--ds-color-text-secondary);
      display: flex;
      align-items: center;
      gap: var(--ds-space-2);
      text-align: left;
    }

    .document-outline-row:hover,
    .document-outline-row.current {
      background: var(--ds-color-accent-soft);
      color: var(--ds-color-text);
    }

    .document-outline-row.current {
      font-weight: 600;
    }

    .document-outline-row:focus-visible {
      outline: 2px solid var(--ds-color-focus);
      outline-offset: -2px;
    }

    .document-outline-label {
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }
</style>
