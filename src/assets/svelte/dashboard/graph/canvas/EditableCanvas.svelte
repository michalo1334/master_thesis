<script lang="ts">
  import type {
    CreateConnectionDraftPayload,
    GraphConnectivityRule,
  } from "../../../contracts.generated/dashboard/graph";
  import type { Node } from "../../../contracts.generated/graph";
  import { onMount } from "svelte";
  import TopologyCanvas, {
    type TopologyAddRequest,
    type TopologyViewCommand,
  } from "../unified/TopologyCanvas.svelte";
  import TopologyToolbar from "../unified/TopologyToolbar.svelte";
  import TopologyNavigator from "../unified/TopologyNavigator.svelte";
  import UnplacedTray from "../unified/UnplacedTray.svelte";
  import { arrangeTopology } from "../unified/layout";
  import {
    buildTopologyScene,
    type TopologyEntitySelection,
  } from "../topology-scene";
  import type {
    ConnectionOption,
    EditableGraphDocument,
  } from "../EditableGraphDocument.svelte";
  import type { DashboardApi } from "../../dashboard-api";
  import OptionPickerDialog from "../../../ui-kit/composites/OptionPickerDialog.svelte";
  import type { FilterableTableColumn } from "../../../ui-kit/composites/FilterableTable.types";

  interface ConnectionRequest {
    position: { x: number; y: number };
    targetId?: string;
    options: readonly ConnectionOption[];
  }

  interface Props {
    document: EditableGraphDocument;
    api: DashboardApi;
    onCompareGraphs?: () => void;
  }

  let { document, api, onCompareGraphs = undefined }: Props = $props();
  let connection = $state<ConnectionRequest>();
  let connectionPickerOpen = $state(false);
  let connectivityRules = $state<readonly GraphConnectivityRule[]>([]);
  let navigatorOpen = $state(false);
  let unplacedOpen = $state(false);
  /**
   * Canvas controls share selection with the document and focus with the
   * canvas. Each command carries a fresh token, so two identical commands both
   * run, while the canvas clears a command it already ran.
   */
  let controlToken = $state(0);
  /** Pending viewport command. The canvas clears it once it runs. */
  let viewCommand = $state<TopologyViewCommand>();
  /** Pending add request. The canvas clears it once it runs. */
  let addRequest = $state<TopologyAddRequest>();

  /**
   * The scene joins the accepted projection to the editable graph.
   * Search, the Navigator, and the Unplaced tray read this scene only.
   */
  let scene = $derived(
    buildTopologyScene(document.graph, document.topologyProjection, {
      pendingEntityIds: document.pendingProjectionEntityIds,
    }),
  );
  let selectedEntityId = $derived(
    document.canvasSelection.kind === "node"
      ? document.canvasSelection.nodeId
      : undefined,
  );

  function nextToken(): number {
    controlToken += 1;
    return controlToken;
  }

  /** Selects an entity and asks the canvas to make it legible. */
  function focusEntity(entityId: string): void {
    document.selectNode(entityId);
    viewCommand = { kind: "focus", entityId, token: nextToken() };
  }

  /**
   * Applies a selection from the Navigator or the Unplaced tray.
   *
   * A relationship has no world rectangle unless a projection group contains
   * it, so an edge selection opens the inspector without a viewport command.
   */
  function focusSelection(selection: TopologyEntitySelection): void {
    if (selection.kind === "edge") {
      document.selectEdge(selection.id);
      return;
    }
    focusEntity(selection.id);
  }

  /**
   * Clears a command the canvas already ran.
   *
   * A command stays here until it is acknowledged, so a canvas remount cannot
   * run the same command twice.
   */
  function acknowledgeViewCommand(token: number): void {
    if (viewCommand?.token === token) viewCommand = undefined;
  }

  function acknowledgeAddRequest(token: number): void {
    if (addRequest?.token === token) addRequest = undefined;
  }

  function fitViewport(): void {
    viewCommand = { kind: "fit", token: nextToken() };
  }

  function resetViewport(): void {
    viewCommand = { kind: "reset", token: nextToken() };
  }

  /**
   * Arranges the graph with the deterministic layout.
   *
   * The arranged positions persist as geometry, so the command never requests
   * a new projection. The fit afterwards changes the viewport only.
   */
  function arrangeScene(): void {
    document.setNodePositions(arrangeTopology(scene).positions);
    fitViewport();
  }

  function addFromToolbar(type: Node["type"]): void {
    addRequest = { type, token: nextToken() };
  }

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
  <TopologyToolbar
    editable
    {scene}
    onAdd={addFromToolbar}
    onSearchSelect={focusEntity}
    onArrange={arrangeScene}
    onFit={fitViewport}
    onReset={resetViewport}
    pinnedCount={document.pinnedEntityIds.length}
    onClearPins={() => document.clearPins()}
    unplacedCount={scene.unplaced.length}
    {unplacedOpen}
    onToggleUnplaced={() => (unplacedOpen = !unplacedOpen)}
    {navigatorOpen}
    onToggleNavigator={() => (navigatorOpen = !navigatorOpen)}
  />

  <div class="canvas-stage">
    <TopologyCanvas
      graph={document.graph}
      projection={document.topologyProjection}
      projectionStatus={document.projectionStatus}
      projectionSource={document.acceptedProjection.source}
      pendingEntityIds={document.pendingProjectionEntityIds}
      {viewCommand}
      {addRequest}
      onViewCommandHandled={acknowledgeViewCommand}
      onAddRequestHandled={acknowledgeAddRequest}
      autoFit={document.loaded}
      selectedNodeId={document.canvasSelection.kind === "node"
        ? document.canvasSelection.nodeId
        : undefined}
      selectedEdgeId={document.canvasSelection.kind === "edge"
        ? document.canvasSelection.edgeId
        : undefined}
      pinnedEntityIds={document.pinnedEntityIds}
      onTogglePin={(nodeId) => document.togglePin(nodeId)}
      onClearPins={() => document.clearPins()}
      onGeometryChange={(positions) => document.setNodePositions(positions)}
      onSelectNode={(nodeId) => document.selectNode(nodeId)}
      onSelectEdge={(edgeId) => document.selectEdge(edgeId)}
      onClearSelection={() => document.clearSelection()}
      onCreateConnection={chooseConnection}
      onDeleteSelection={() => document.deleteSelection()}
      onAddNode={addNode}
      {onCompareGraphs}
    />
    {#if navigatorOpen}
      <div class="canvas-navigator">
        <TopologyNavigator
          {scene}
          {selectedEntityId}
          onSelect={focusSelection}
        />
      </div>
    {/if}
  </div>

  {#if unplacedOpen && scene.unplaced.length > 0}
    <div class="canvas-unplaced">
      <UnplacedTray
        {scene}
        onSelect={focusSelection}
        onClose={() => (unplacedOpen = false)}
      />
    </div>
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
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }
  .canvas-stage {
    position: relative;
    flex: 1 1 auto;
    min-height: 0;
  }
  .canvas-navigator {
    position: absolute;
    z-index: 3;
    top: 3.5rem;
    left: var(--ui-space-3);
    max-width: 20rem;
    max-height: calc(100% - 5rem);
  }
  .canvas-unplaced {
    flex: 0 0 auto;
    max-height: 14rem;
    overflow: auto;
    border-top: 1px solid var(--ui-color-border);
  }
</style>
