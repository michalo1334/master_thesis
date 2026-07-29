<script lang="ts">
  import { Dialog } from "bits-ui";
  import type { GraphSummary } from "../contract";

  interface Props {
    open: boolean;
    onOpenChange: (open: boolean) => void;
    summaries: readonly GraphSummary[];
    onSelect: (summary: GraphSummary) => Promise<boolean> | boolean;
    status?: string;
  }

  interface TreeNode {
    summary: GraphSummary;
    children: TreeNode[];
  }

  interface TreeRow {
    summary: GraphSummary;
    depth: number;
  }

  let {
    open,
    onOpenChange,
    summaries,
    onSelect,
    status = "",
  }: Props = $props();

  let isSelecting = $state(false);
  let selectionError = $state("");

  const tree = $derived.by(() => buildTree(summaries));
  const rows = $derived.by(() => flattenTree(tree));
  const displayStatus = $derived(status || selectionError);

  function buildTree(summaries: readonly GraphSummary[]): TreeNode[] {
    const nodes = new Map<string, TreeNode>(
      summaries.map((summary): [string, TreeNode] => [
        summary.id,
        { summary, children: [] },
      ]),
    );
    const roots: TreeNode[] = [];

    for (const node of nodes.values()) {
      const parent = node.summary.parentId
        ? nodes.get(node.summary.parentId)
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

  function flattenTree(nodes: readonly TreeNode[]): TreeRow[] {
    const rows: TreeRow[] = [];

    const visit = (items: readonly TreeNode[], depth: number): void => {
      for (const node of items) {
        rows.push({ summary: node.summary, depth });
        visit(node.children, depth + 1);
      }
    };

    visit(nodes, 0);
    return rows;
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
</script>

<Dialog.Root {open} {onOpenChange}>
  {#if open}
    <Dialog.Portal>
      <Dialog.Overlay class="graph-tree-picker-overlay" />
      <Dialog.Content class="graph-tree-picker-dialog">
        <Dialog.Title>Open graph</Dialog.Title>
        <Dialog.Description>
          Select a saved graph to open in the workspace.
        </Dialog.Description>

        <div class="graph-tree-picker-body">
          {#if rows.length}
            <table class="graph-tree-picker-table">
              <thead>
                <tr>
                  <th>Graph</th>
                  <th>Tags</th>
                  <th class="graph-tree-align-end">Nodes</th>
                  <th class="graph-tree-align-end">Edges</th>
                </tr>
              </thead>
              <tbody>
                {#each rows as row (row.summary.id)}
                  <tr
                    data-depth={row.depth}
                    data-disabled={isSelecting || undefined}
                  >
                    <td class="graph-tree-graph">
                      <button
                        type="button"
                        class="graph-tree-row"
                        disabled={isSelecting}
                        style:--depth={row.depth}
                        onclick={() => select(row.summary)}
                      >
                        <span class="graph-tree-title">{row.summary.title}</span
                        >
                      </button>
                    </td>
                    <td class="graph-tree-tags">
                      {#each row.summary.tags as tag (tag)}
                        <span class="graph-tree-tag">{tag}</span>
                      {/each}
                    </td>
                    <td class="graph-tree-align-end">{row.summary.nodeCount}</td
                    >
                    <td class="graph-tree-align-end">{row.summary.edgeCount}</td
                    >
                  </tr>
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
    background: color-mix(in srgb, var(--ds-color-nav) 45%, transparent);
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
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-lg);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-md);
    color: var(--ds-color-text);
    transform: translate(-50%, -50%);
  }

  :global(.graph-tree-picker-dialog [data-dialog-title]) {
    margin: 0;
    font-size: var(--ds-text-xl);
  }

  :global(.graph-tree-picker-dialog [data-dialog-description]) {
    margin: var(--ds-space-2) 0 0;
    color: var(--ds-color-text-secondary);
  }

  .graph-tree-picker-body {
    min-height: 0;
    margin-top: var(--ds-space-4);
    overflow: auto;
    border: 1px solid var(--ds-color-border-soft);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
  }

  .graph-tree-picker-table {
    width: 100%;
    min-width: 36rem;
    border-collapse: collapse;
    font-size: var(--ds-text-sm);
  }

  .graph-tree-picker-table th {
    position: sticky;
    top: 0;
    z-index: 1;
    padding: var(--ds-space-2) var(--ds-space-3);
    border-bottom: 1px solid var(--ds-color-border);
    background: var(--ds-color-surface);
    color: var(--ds-color-text-secondary);
    font-weight: 600;
    text-align: start;
    white-space: nowrap;
  }

  .graph-tree-picker-table td {
    padding: var(--ds-space-2) var(--ds-space-3);
    border-bottom: 1px solid var(--ds-color-border-soft);
    color: var(--ds-color-text);
    vertical-align: middle;
  }

  .graph-tree-picker-table tbody tr:last-child td {
    border-bottom: 0;
  }

  .graph-tree-picker-table tbody tr:not([data-disabled]):hover {
    background: var(--ds-color-accent-soft);
  }

  .graph-tree-picker-table tbody tr[data-disabled] {
    color: var(--ds-color-text-faint);
  }

  .graph-tree-picker-table tbody tr[data-disabled] td {
    color: var(--ds-color-text-faint);
  }

  .graph-tree-graph {
    padding: 0 !important;
  }

  .graph-tree-row {
    --indent-step: 1.5rem;

    display: block;
    width: 100%;
    min-height: var(--ds-control-height);
    padding: var(--ds-space-2) var(--ds-space-3);
    padding-inline-start: calc(
      var(--ds-space-3) + var(--depth, 0) * var(--indent-step)
    );
    border: 0;
    background: transparent;
    color: inherit;
    text-align: left;
  }

  .graph-tree-row:focus-visible {
    outline: 2px solid var(--ds-color-focus);
    outline-offset: -2px;
  }

  .graph-tree-row:disabled {
    cursor: default;
    color: var(--ds-color-text-faint);
  }

  .graph-tree-title {
    display: block;
    overflow: hidden;
    font-weight: 600;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .graph-tree-tags {
    min-width: 10rem;
  }

  .graph-tree-tag {
    display: inline-block;
    margin: 0 var(--ds-space-1) var(--ds-space-1) 0;
    padding: 0 0.375rem;
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-accent-soft);
    color: var(--ds-color-text);
  }

  .graph-tree-align-end {
    text-align: end !important;
    font-variant-numeric: tabular-nums;
  }

  .graph-tree-empty,
  .graph-tree-status {
    margin: 0;
    padding: var(--ds-space-2) var(--ds-space-3);
    border-radius: var(--ds-radius-sm);
    font-size: var(--ds-text-sm);
  }

  .graph-tree-empty {
    color: var(--ds-color-text-secondary);
  }

  .graph-tree-status {
    margin-top: var(--ds-space-3);
    background: var(--ds-color-warning-bg);
    color: var(--ds-color-warning-text);
  }

  .graph-tree-picker-actions {
    display: flex;
    justify-content: flex-end;
    margin-top: var(--ds-space-4);
  }

  :global(.graph-tree-picker-button) {
    min-height: var(--ds-control-height);
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-surface);
    color: inherit;
  }

  :global(.graph-tree-picker-button:not(:disabled):hover) {
    filter: brightness(0.96);
  }

  @media (max-width: 30rem) {
    :global(.graph-tree-picker-dialog) {
      width: calc(100vw - 1rem);
      max-height: calc(100dvh - 1rem);
      padding: var(--ds-space-3);
    }
  }
</style>
