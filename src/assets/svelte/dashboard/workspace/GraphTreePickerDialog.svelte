<script lang="ts">
  import type { GraphSummary } from "../../contracts.generated/dashboard/graph";
  import { Button, Dialog } from "bits-ui";
  import { SvelteSet } from "svelte/reactivity";
  import Icon from "../../ui-kit/primitives/Icon.svelte";
  interface Props {
    open: boolean;
    onOpenChange: (open: boolean) => void;
    summaries: readonly GraphSummary[];
    onSelect: (summary: GraphSummary) => Promise<boolean> | boolean;
    onFavoriteChange: (
      summary: GraphSummary,
      favorite: boolean,
    ) => Promise<boolean> | boolean;
    title?: string;
    description?: string;
    status?: string;
    selectedRevisionId?: string;
  }

  interface TreeNode {
    summary: GraphSummary;
    children: TreeNode[];
  }

  interface TreeRow {
    summary: GraphSummary;
    depth: number;
    hasChildren: boolean;
  }

  let {
    open,
    onOpenChange,
    summaries,
    onSelect,
    onFavoriteChange,
    title = "Open graph",
    description = "Select a saved graph to open in the workspace.",
    status = "",
    selectedRevisionId = undefined,
  }: Props = $props();

  let isSelecting = $state(false);
  let isFavoriting = $state(false);
  let selectionError = $state("");
  let favoriteError = $state("");
  const expandedGraphIds = new SvelteSet<string>();
  const id = $props.id();

  const tree = $derived.by(() => buildTree(summaries));
  const visibleRows = $derived.by(() => flattenTree(tree, expandedGraphIds));
  const favorites = $derived(
    summaries.filter((summary) => summary.is_favorite),
  );
  const displayStatus = $derived(status || selectionError || favoriteError);

  function buildTree(summaries: readonly GraphSummary[]): TreeNode[] {
    const nodes = new Map<string, TreeNode>(
      summaries.map((summary): [string, TreeNode] => [
        summary.revision_id,
        { summary, children: [] },
      ]),
    );
    const roots: TreeNode[] = [];

    for (const node of nodes.values()) {
      const parent = node.summary.parent_revision_id
        ? nodes.get(node.summary.parent_revision_id)
        : undefined;
      if (parent && parent !== node) parent.children.push(node);
      else roots.push(node);
    }

    const sortNodes = (items: TreeNode[]): TreeNode[] => {
      items.sort((a, b) => a.summary.title.localeCompare(b.summary.title));
      for (const item of items) sortNodes(item.children);
      return items;
    };

    return sortNodes(roots);
  }

  function flattenTree(
    nodes: readonly TreeNode[],
    expanded: ReadonlySet<string>,
  ): TreeRow[] {
    const rows: TreeRow[] = [];

    const visit = (items: readonly TreeNode[], depth: number): void => {
      for (const node of items) {
        rows.push({
          summary: node.summary,
          depth,
          hasChildren: node.children.length > 0,
        });
        if (expanded.has(node.summary.revision_id))
          visit(node.children, depth + 1);
      }
    };

    visit(nodes, 0);
    return rows;
  }

  function toggleGraph(revisionId: string): void {
    if (expandedGraphIds.has(revisionId)) expandedGraphIds.delete(revisionId);
    else expandedGraphIds.add(revisionId);
  }

  function expandAllGraphs(): void {
    const visit = (nodes: readonly TreeNode[]): void => {
      for (const node of nodes) {
        if (node.children.length)
          expandedGraphIds.add(node.summary.revision_id);
        visit(node.children);
      }
    };

    expandedGraphIds.clear();
    visit(tree);
  }

  function collapseAllGraphs(): void {
    expandedGraphIds.clear();
  }

  function handleOpenChange(nextOpen: boolean): void {
    if (!nextOpen) collapseAllGraphs();
    onOpenChange(nextOpen);
  }

  async function select(summary: GraphSummary): Promise<void> {
    if (isSelecting) return;

    isSelecting = true;
    selectionError = "";
    try {
      if (await onSelect(summary)) onOpenChange(false);
    } catch {
      if (!status) selectionError = "Unable to open graph. Please try again.";
    } finally {
      isSelecting = false;
    }
  }

  async function changeFavorite(
    event: MouseEvent,
    summary: GraphSummary,
  ): Promise<void> {
    event.stopPropagation();
    if (isFavoriting) return;

    isFavoriting = true;
    favoriteError = "";
    try {
      if (!(await onFavoriteChange(summary, !summary.is_favorite)) && !status) {
        favoriteError = "Unable to update favourite.";
      }
    } catch {
      if (!status) favoriteError = "Unable to update favourite.";
    } finally {
      isFavoriting = false;
    }
  }
</script>

{#snippet graphRow(row: TreeRow, location: "favourite" | "tree")}
  <tr
    data-depth={location === "tree" ? row.depth : undefined}
    data-disabled={isSelecting || isFavoriting || undefined}
    data-graph-location={location}
    data-revision-id={row.summary.revision_id}
    data-selected={selectedRevisionId === row.summary.revision_id || undefined}
  >
    <td class="graph-tree-graph">
      <div
        class="graph-tree-row"
        style:--depth={location === "tree" ? row.depth : 0}
      >
        {#if location === "tree" && row.hasChildren}
          <Button.Root
            type="button"
            class="graph-tree-toggle"
            aria-label={`${expandedGraphIds.has(row.summary.revision_id) ? "Collapse" : "Expand"} ${row.summary.title}`}
            aria-expanded={expandedGraphIds.has(row.summary.revision_id)}
            disabled={isSelecting || isFavoriting}
            onclick={() => toggleGraph(row.summary.revision_id)}
          >
            <Icon
              name={expandedGraphIds.has(row.summary.revision_id)
                ? "chevron-down"
                : "chevron-right"}
              size={18}
            />
          </Button.Root>
        {/if}
        <input
          class="graph-tree-selection"
          type="checkbox"
          checked={selectedRevisionId === row.summary.revision_id}
          aria-hidden="true"
          tabindex="-1"
          disabled
        />
        <button
          type="button"
          class="graph-tree-select"
          disabled={isSelecting || isFavoriting}
          onclick={() => select(row.summary)}
        >
          <span class="graph-tree-title">{row.summary.title}</span>
        </button>
        <button
          type="button"
          class="graph-tree-favorite"
          aria-label={`${row.summary.is_favorite ? "Remove" : "Add"} ${row.summary.title} ${row.summary.is_favorite ? "from" : "to"} favourites`}
          aria-pressed={row.summary.is_favorite}
          disabled={isSelecting || isFavoriting}
          onclick={(event) => changeFavorite(event, row.summary)}
        >
          <Icon name={row.summary.is_favorite ? "star-filled" : "star"} />
        </button>
      </div>
    </td>
    <td class="graph-tree-revision">
      {row.summary.revision_kind} #{row.summary.revision_number}
    </td>
    <td class="graph-tree-align-end">{row.summary.node_count}</td>
    <td class="graph-tree-align-end">{row.summary.edge_count}</td>
  </tr>
{/snippet}

<Dialog.Root {open} onOpenChange={handleOpenChange}>
  {#if open}
    <Dialog.Portal>
      <Dialog.Overlay class="graph-tree-picker-overlay" />
      <Dialog.Content class="graph-tree-picker-dialog">
        <Dialog.Title>{title}</Dialog.Title>
        <Dialog.Description>{description}</Dialog.Description>

        <div class="graph-tree-picker-body">
          {#if summaries.length}
            <div class="graph-tree-toolbar">
              <Button.Root
                type="button"
                onclick={expandAllGraphs}
                disabled={isSelecting}
              >
                Expand all
              </Button.Root>
              <Button.Root
                type="button"
                onclick={collapseAllGraphs}
                disabled={isSelecting}
              >
                Collapse all
              </Button.Root>
            </div>
            <table class="graph-tree-picker-table">
              <thead>
                <tr>
                  <th>Graph</th>
                  <th>Revision</th>
                  <th class="graph-tree-align-end">Nodes</th>
                  <th class="graph-tree-align-end">Edges</th>
                </tr>
              </thead>
              {#if favorites.length}
                <tbody aria-labelledby={`${id}-favourites`}>
                  <tr class="graph-tree-section-heading">
                    <th id={`${id}-favourites`} colspan="4" scope="colgroup">
                      Favourites
                    </th>
                  </tr>
                  {#each favorites as favorite (favorite.revision_id)}
                    {@render graphRow(
                      { summary: favorite, depth: 0, hasChildren: false },
                      "favourite",
                    )}
                  {/each}
                </tbody>
              {/if}
              <tbody>
                {#each visibleRows as row (row.summary.revision_id)}
                  {@render graphRow(row, "tree")}
                {/each}
              </tbody>
            </table>
          {:else}
            <p class="graph-tree-empty">No saved graphs.</p>
          {/if}
        </div>

        {#if displayStatus}
          <p class="graph-tree-status" role="alert">{displayStatus}</p>
        {/if}

        <div class="graph-tree-picker-actions">
          <Dialog.Close class="graph-tree-picker-button" disabled={isSelecting}>
            Cancel
          </Dialog.Close>
        </div>
      </Dialog.Content>
    </Dialog.Portal>
  {/if}
</Dialog.Root>

<style>
  :global(.graph-tree-picker-overlay) {
    position: fixed;
    z-index: 200;
    inset: 0;
    background: color-mix(in srgb, var(--ui-color-nav) 45%, transparent);
  }

  :global(.graph-tree-picker-dialog) {
    position: fixed;
    z-index: 201;
    top: 50%;
    left: 50%;
    width: min(64rem, calc(100vw - 2rem));
    max-height: min(40rem, calc(100dvh - 2rem));
    display: grid;
    grid-template-rows: auto auto minmax(0, 1fr) auto auto;
    padding: 1.5rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-lg);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
    color: var(--ui-color-text);
    transform: translate(-50%, -50%);
  }

  :global(.graph-tree-picker-dialog [data-dialog-title]) {
    margin: 0;
    font-size: var(--ui-text-xl);
  }

  :global(.graph-tree-picker-dialog [data-dialog-description]) {
    margin: var(--ui-space-2) 0 0;
    color: var(--ui-color-text-secondary);
  }

  .graph-tree-picker-body {
    min-height: 0;
    margin-top: var(--ui-space-4);
    overflow: auto;
    border: 1px solid var(--ui-color-border-soft);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
  }

  .graph-tree-picker-table {
    width: 100%;
    min-width: 36rem;
    border-collapse: collapse;
    font-size: var(--ui-text-sm);
  }

  .graph-tree-toolbar {
    display: flex;
    gap: var(--ui-space-2);
    padding: var(--ui-space-2);
    border-bottom: 1px solid var(--ui-color-border-soft);
  }

  .graph-tree-toolbar :global(button),
  :global(.graph-tree-toggle) {
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-surface);
    color: inherit;
  }

  .graph-tree-toolbar :global(button) {
    min-height: var(--ui-control-height);
    padding: 0.375rem 0.75rem;
  }

  .graph-tree-picker-table th {
    position: sticky;
    top: 0;
    z-index: 1;
    padding: var(--ui-space-2) var(--ui-space-3);
    border-bottom: 1px solid var(--ui-color-border);
    background: var(--ui-color-surface);
    color: var(--ui-color-text-secondary);
    font-weight: 600;
    text-align: start;
    white-space: nowrap;
  }

  .graph-tree-picker-table td {
    padding: var(--ui-space-2) var(--ui-space-3);
    border-bottom: 1px solid var(--ui-color-border-soft);
    color: var(--ui-color-text);
    vertical-align: middle;
  }

  .graph-tree-section-heading th {
    position: static;
    padding: var(--ui-space-2) var(--ui-space-3);
    border-bottom: 1px solid var(--ui-color-border-soft);
    background: var(--ui-color-accent-soft);
    color: var(--ui-color-text);
    font-weight: 600;
    text-align: left;
  }

  .graph-tree-picker-table tbody tr:last-child td {
    border-bottom: 0;
  }

  .graph-tree-picker-table tbody tr:not([data-disabled]):hover {
    background: var(--ui-color-accent-soft);
  }

  .graph-tree-picker-table tbody tr[data-selected] {
    background: var(--ui-color-accent-soft);
  }

  .graph-tree-picker-table tbody tr[data-selected] .graph-tree-title {
    color: var(--ui-color-accent);
  }

  .graph-tree-picker-table tbody tr[data-disabled] {
    color: var(--ui-color-text-faint);
  }

  .graph-tree-picker-table tbody tr[data-disabled] td {
    color: var(--ui-color-text-faint);
  }

  .graph-tree-graph {
    padding: 0 !important;
  }

  .graph-tree-row {
    --indent-step: 1.5rem;

    display: flex;
    align-items: center;
    width: 100%;
    min-height: var(--ui-control-height);
    padding-inline-start: calc(
      var(--ui-space-3) + var(--depth, 0) * var(--indent-step)
    );
  }

  :global(.graph-tree-toggle) {
    display: grid;
    width: 1.5rem;
    height: 1.5rem;
    flex: none;
    place-items: center;
  }

  .graph-tree-selection {
    width: 1rem;
    height: 1rem;
    flex: none;
    margin: 0 var(--ui-space-2);
    accent-color: var(--ui-color-accent);
  }

  .graph-tree-select {
    width: 100%;
    min-height: var(--ui-control-height);
    padding: var(--ui-space-2) var(--ui-space-3);
    border: 0;
    background: transparent;
    color: inherit;
    text-align: left;
  }

  .graph-tree-favorite {
    display: grid;
    width: var(--ui-control-height);
    min-height: var(--ui-control-height);
    flex: none;
    place-items: center;
    border: 0;
    background: transparent;
    color: var(--ui-color-text-secondary);
  }

  .graph-tree-favorite[aria-pressed="true"] {
    color: var(--ui-color-accent);
  }

  :global(.graph-tree-toggle:focus-visible),
  .graph-tree-select:focus-visible,
  .graph-tree-favorite:focus-visible {
    outline: 2px solid var(--ui-color-focus);
    outline-offset: -2px;
  }

  .graph-tree-select:disabled,
  .graph-tree-favorite:disabled,
  :global(.graph-tree-toggle:disabled),
  .graph-tree-toolbar :global(button:disabled) {
    cursor: default;
    color: var(--ui-color-text-faint);
  }

  .graph-tree-title {
    display: block;
    overflow: hidden;
    font-weight: 600;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .graph-tree-revision {
    min-width: 10rem;
  }

  .graph-tree-align-end {
    text-align: end !important;
    font-variant-numeric: tabular-nums;
  }

  .graph-tree-empty,
  .graph-tree-status {
    margin: 0;
    padding: var(--ui-space-2) var(--ui-space-3);
    border-radius: var(--ui-radius-sm);
    font-size: var(--ui-text-sm);
  }

  .graph-tree-empty {
    color: var(--ui-color-text-secondary);
  }

  .graph-tree-status {
    margin-top: var(--ui-space-3);
    background: var(--ui-color-warning-bg);
    color: var(--ui-color-warning-text);
  }

  .graph-tree-picker-actions {
    display: flex;
    justify-content: flex-end;
    margin-top: var(--ui-space-4);
  }

  :global(.graph-tree-picker-button) {
    min-height: var(--ui-control-height);
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-surface);
    color: inherit;
  }

  :global(.graph-tree-picker-button:not(:disabled):hover) {
    filter: brightness(0.96);
  }

  @media (max-width: 30rem) {
    :global(.graph-tree-picker-dialog) {
      width: calc(100vw - 1rem);
      max-height: calc(100dvh - 1rem);
      padding: var(--ui-space-3);
    }
  }
</style>
