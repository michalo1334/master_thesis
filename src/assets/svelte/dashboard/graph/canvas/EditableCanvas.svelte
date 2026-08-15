<script lang="ts">
  import { onMount } from "svelte";
  import Canvas from "./Canvas.svelte";
  import NetworkCanvas from "../network/NetworkCanvas.svelte";
  import type {
    ConnectionOption,
    EditableGraphDocument,
  } from "../EditableGraphDocument.svelte";
  import type { DashboardApi } from "../../dashboard-api";
  import type {
    CreateConnectionDraftPayload,
    GraphConnectivityRule,
    Node,
  } from "../../contract";
  import OptionPickerDialog from "../../ui/OptionPickerDialog.svelte";
  import type { FilterableTableColumn } from "../../controls/FilterableTable.types";

  interface ConnectionRequest {
    position: { x: number; y: number };
    targetId?: string;
    options: readonly ConnectionOption[];
  }

  interface Props {
    document: EditableGraphDocument;
    api: DashboardApi;
    onCompareGraphs?: () => void;
    onArrangeNetwork?: () => void;
  }

  let {
    document,
    api,
    onCompareGraphs = undefined,
    onArrangeNetwork = undefined,
  }: Props = $props();
  let connection = $state<ConnectionRequest>();
  let connectionPickerOpen = $state(false);
  let connectivityRules = $state<readonly GraphConnectivityRule[]>([]);
  let canvasMode = $state<"topology" | "network">("topology");

  onMount(() => {
    let active = true;
    void api
      .fetchGraphConnectivity()
      .then((reply) => {
        if (active) connectivityRules = reply.rules;
      })
      .catch(() => {});
    return () => {
      active = false;
    };
  });

  const columns: readonly FilterableTableColumn<ConnectionOption>[] = [
    { key: "choice", header: "Choice", getValue: optionLabel },
    { key: "details", header: "Details", getValue: optionDetails },
  ];

  function optionLabel(option: ConnectionOption): string {
    return option.target.id
      ? option.relationshipType
      : `${option.target.type} via ${option.relationshipType}`;
  }

  function optionDetails(option: ConnectionOption): string {
    const from = option.source.isFrom ? option.source.type : option.target.type;
    const to = option.source.isFrom ? option.target.type : option.source.type;
    return `${from} → ${to}`;
  }

  function optionKey(option: ConnectionOption): string {
    return `${option.relationshipType}:${option.source.id}:${option.target.id ?? option.target.type}:${option.source.isFrom}`;
  }

  function chooseConnection(
    sourceId: string,
    targetId: string | undefined,
    position: { x: number; y: number },
  ) {
    const source = document.graph.nodes.find((node) => node.id === sourceId);
    const target = document.graph.nodes.find((node) => node.id === targetId);
    if (!source || (targetId && !target)) return;

    connection = {
      position,
      targetId,
      options: connectionOptions(source, target),
    };
    connectionPickerOpen = true;
  }

  function connectionOptions(source: Node, target?: Node): ConnectionOption[] {
    return connectivityRules.flatMap((rule) => {
      if (target) {
        if (rule.from_type === source.type && rule.to_type === target.type)
          return [optionFor(rule, source, target, source.id)];
        if (rule.from_type === target.type && rule.to_type === source.type)
          return [optionFor(rule, target, source, source.id)];
        return [];
      }
      if (rule.from_type === source.type)
        return [newNodeOption(rule, source, rule.to_type, true)];
      if (rule.to_type === source.type)
        return [newNodeOption(rule, source, rule.from_type, false)];
      return [];
    });
  }

  function optionFor(
    rule: GraphConnectivityRule,
    from: Node,
    to: Node,
    sourceId: string,
  ): ConnectionOption {
    return {
      relationshipType: rule.relationship_type,
      source: {
        id: sourceId,
        type: sourceId === from.id ? from.type : to.type,
        isFrom: sourceId === from.id,
      },
      target: {
        id: sourceId === from.id ? to.id : from.id,
        type: sourceId === from.id ? to.type : from.type,
      },
    };
  }

  function newNodeOption(
    rule: GraphConnectivityRule,
    source: Node,
    newNodeType: Node["type"],
    sourceIsFrom: boolean,
  ): ConnectionOption {
    return {
      relationshipType: rule.relationship_type,
      source: { id: source.id, type: source.type, isFrom: sourceIsFrom },
      target: { type: newNodeType },
    };
  }

  function connectionDraftPayload(
    choice: ConnectionOption,
    position: { x: number; y: number },
  ): CreateConnectionDraftPayload {
    const source = {
      relationship_type: choice.relationshipType,
      source_id: choice.source.id,
      source_type: choice.source.type,
      source_is_from: choice.source.isFrom,
    };

    if (choice.target.id) {
      return {
        ...source,
        target_id: choice.target.id,
        target_type: choice.target.type,
      } as CreateConnectionDraftPayload;
    }

    return {
      ...source,
      new_node_type: choice.target.type,
      x_pos: position.x,
      y_pos: position.y,
    } as CreateConnectionDraftPayload;
  }

  async function createConnection(
    options: ConnectionOption[],
  ): Promise<boolean> {
    const choice = options[0];
    if (!connection || !choice) return false;

    const reply = await api.createConnectionDraft(
      connectionDraftPayload(choice, connection.position),
    );
    if (reply.status !== "ok" || !reply.edge) return false;

    document.createConnection(reply.edge, reply.node ?? undefined);
    return true;
  }

  async function addNode(
    type: Node["type"],
    position: { x: number; y: number },
  ) {
    const reply = await api.createNodeDraft({
      node_type: type,
      x_pos: position.x,
      y_pos: position.y,
    });
    if (reply.status === "ok" && reply.node) document.addNode(reply.node);
  }

  function setConnectionPickerOpen(open: boolean) {
    connectionPickerOpen = open;
    if (!open) connection = undefined;
  }
</script>

<div class="editable-canvas">
  <div class="canvas-mode-toggle" role="group" aria-label="Graph view">
    <button
      type="button"
      aria-pressed={canvasMode === "topology"}
      onclick={() => (canvasMode = "topology")}>Topology</button
    >
    <button
      type="button"
      aria-pressed={canvasMode === "network"}
      onclick={() => (canvasMode = "network")}>Network</button
    >
  </div>

  {#if canvasMode === "topology"}
    <Canvas
      graph={document.graph}
      fitVersion={document.revision}
      selectedNodeId={document.canvasSelection.kind === "node"
        ? document.canvasSelection.nodeId
        : undefined}
      selectedEdgeId={document.canvasSelection.kind === "edge"
        ? document.canvasSelection.edgeId
        : undefined}
      onGraphChange={(graph) => (document.graph = graph)}
      onSelectNode={(nodeId) => document.selectNode(nodeId)}
      onSelectEdge={(edgeId) => document.selectEdge(edgeId)}
      onClearSelection={() => document.clearSelection()}
      onCreateConnection={chooseConnection}
      onDeleteSelection={() => document.deleteSelection()}
      onAddNode={addNode}
      connectionRules={connectivityRules}
      {onCompareGraphs}
    />
  {:else}
    <NetworkCanvas {document} {api} {onArrangeNetwork} />
  {/if}
</div>

<OptionPickerDialog
  open={connectionPickerOpen}
  onOpenChange={setConnectionPickerOpen}
  items={connection?.options ?? []}
  title="Create connection"
  description={connection?.targetId
    ? "Choose a valid connection direction."
    : "Choose a valid connection."}
  getKey={optionKey}
  {columns}
  emptyMessage="No valid connections are available."
  noMatchMessage="No matching connections."
  searchPlaceholder="Search connections…"
  onConfirm={createConnection}
/>

<style>
  .editable-canvas {
    position: relative;
    height: 100%;
    min-height: 0;
  }
  .canvas-mode-toggle {
    position: absolute;
    z-index: 2;
    top: var(--ds-space-3);
    left: var(--ds-space-3);
    display: flex;
    overflow: hidden;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-md);
  }
  .canvas-mode-toggle button {
    min-height: 2rem;
    border: 0;
    border-right: 1px solid var(--ds-color-border);
    background: transparent;
    color: var(--ds-color-text-secondary);
    padding: 0 0.625rem;
  }
  .canvas-mode-toggle button:last-child {
    border-right: 0;
  }
  .canvas-mode-toggle button[aria-pressed="true"] {
    background: var(--ds-color-accent-soft);
    color: var(--ds-color-text);
    font-weight: 700;
  }
</style>
