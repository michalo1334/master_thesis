<script lang="ts">
  import { ContextMenu } from "bits-ui";
  import CanvasEdge from "./canvas/CanvasEdge.svelte";
  import CanvasNode from "./canvas/CanvasNode.svelte";
  import {
    cloneFixtureGraph,
    createFixtureNode,
    nodeCenter,
    type AssetKind,
    type CanvasEdgeData,
    type CanvasNodeData,
    type GraphPoint,
  } from "./canvas/fixtures";

  const MIN_ZOOM = 25;
  const MAX_ZOOM = 200;
  const ZOOM_STEP = 10;
  const PAN_STEP = 40;
  const DRAG_THRESHOLD = 4;

  interface Props {
    tool: "select" | "connect";
    placementKind?: AssetKind;
    onPlacementConsumed: () => void;
    onSelectionChange: (selection?: { id: string; name: string }) => void;
    onEdgeCreated: () => void;
  }

  let {
    tool,
    placementKind,
    onPlacementConsumed,
    onSelectionChange,
    onEdgeCreated,
  }: Props = $props();
  const canvasPreviewArrowId = $props.id();
  const fixtureGraph = cloneFixtureGraph();
  let nodes = $state<CanvasNodeData[]>(fixtureGraph.nodes);
  let edges = $state<CanvasEdgeData[]>(fixtureGraph.edges);
  let zoom = $state(100);
  let pan = $state({ x: 0, y: 0 });
  let selectedId = $state<string>();
  let connectionSourceId = $state<string>();
  let pointerGraphPosition = $state<GraphPoint>();
  let contextGraphPosition = $state<GraphPoint>({ x: 0, y: 0 });
  let viewport = $state({ width: 0, height: 0 });
  let didPan = $state(false);
  let suppressNodeClick = $state(false);
  let drag:
    | {
        pointerId: number;
        startX: number;
        startY: number;
        panX: number;
        panY: number;
      }
    | undefined;
  let nodeDrag = $state<
    | {
        pointerId: number;
        nodeId: string;
        startX: number;
        startY: number;
        nodeX: number;
        nodeY: number;
        moved: boolean;
        element: SVGGElement;
      }
    | undefined
  >();
  let gridSize = $derived(20 * (zoom / 100));
  let worldTransform = $derived(
    `translate(${pan.x} ${pan.y}) scale(${zoom / 100})`,
  );
  let connectionSource = $derived(
    nodes.find((node) => node.id === connectionSourceId),
  );

  function clampZoom(value: number) {
    return Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, value));
  }

  function setZoom(value: number) {
    zoom = clampZoom(value);
  }

  function panBy(x: number, y: number) {
    pan = { x: pan.x + x, y: pan.y + y };
  }

  function resetView() {
    zoom = 100;
    pan = { x: 0, y: 0 };
  }

  function graphPosition(event: PointerEvent | MouseEvent): GraphPoint {
    const surface = event.currentTarget as HTMLElement;
    const bounds = surface.getBoundingClientRect();
    const scale = zoom / 100;

    return {
      x: (event.clientX - bounds.left - pan.x) / scale,
      y: (event.clientY - bounds.top - pan.y) / scale,
    };
  }

  function isGraphInteractive(target: EventTarget | null) {
    return (
      target instanceof Element &&
      Boolean(target.closest("[data-graph-interactive]"))
    );
  }

  function handlePointerDown(event: PointerEvent) {
    if (
      event.button !== 0 ||
      !event.isPrimary ||
      isGraphInteractive(event.target)
    )
      return;

    const surface = event.currentTarget as HTMLDivElement;
    surface.focus();
    surface.setPointerCapture(event.pointerId);
    didPan = false;
    drag = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      panX: pan.x,
      panY: pan.y,
    };
  }

  function startNodeDrag(node: CanvasNodeData, event: PointerEvent) {
    if (event.button !== 0 || !event.isPrimary) return;

    event.stopPropagation();
    const element = event.currentTarget as SVGGElement;
    element.setPointerCapture(event.pointerId);
    nodeDrag = {
      pointerId: event.pointerId,
      nodeId: node.id,
      startX: event.clientX,
      startY: event.clientY,
      nodeX: node.x,
      nodeY: node.y,
      moved: false,
      element,
    };
  }

  function handlePointerMove(event: PointerEvent) {
    pointerGraphPosition = graphPosition(event);
    if (nodeDrag?.pointerId === event.pointerId) {
      const deltaX = event.clientX - nodeDrag.startX;
      const deltaY = event.clientY - nodeDrag.startY;

      if (!nodeDrag.moved && Math.hypot(deltaX, deltaY) >= DRAG_THRESHOLD)
        nodeDrag.moved = true;
      if (!nodeDrag.moved) return;

      const scale = zoom / 100;
      nodes = nodes.map((node) =>
        node.id === nodeDrag?.nodeId
          ? {
              ...node,
              x: nodeDrag.nodeX + deltaX / scale,
              y: nodeDrag.nodeY + deltaY / scale,
            }
          : node,
      );
      return;
    }
    if (!drag || drag.pointerId !== event.pointerId) return;

    didPan ||= event.clientX !== drag.startX || event.clientY !== drag.startY;
    pan = {
      x: drag.panX + event.clientX - drag.startX,
      y: drag.panY + event.clientY - drag.startY,
    };
  }

  function releasePointer(event: PointerEvent) {
    if (!drag || drag.pointerId !== event.pointerId) return;

    const surface = event.currentTarget as HTMLDivElement;
    if (surface.hasPointerCapture(event.pointerId))
      surface.releasePointerCapture(event.pointerId);
  }

  function endNodeDrag(event: PointerEvent) {
    if (!nodeDrag || nodeDrag.pointerId !== event.pointerId) return;

    if (nodeDrag.element.hasPointerCapture(event.pointerId))
      nodeDrag.element.releasePointerCapture(event.pointerId);
    if (event.type === "pointerup" && nodeDrag.moved) suppressNodeClick = true;
    nodeDrag = undefined;
  }

  function handlePointerUp(event: PointerEvent) {
    if (nodeDrag?.pointerId === event.pointerId) {
      endNodeDrag(event);
      return;
    }
    if (!drag || drag.pointerId !== event.pointerId) return;

    releasePointer(event);
    drag = undefined;
  }

  function cancelPan(event: PointerEvent) {
    if (nodeDrag?.pointerId === event.pointerId) {
      endNodeDrag(event);
      return;
    }
    releasePointer(event);
    drag = undefined;
  }

  function handleWheel(event: WheelEvent) {
    event.preventDefault();
    setZoom(zoom + (event.deltaY < 0 ? ZOOM_STEP : -ZOOM_STEP));
  }

  function selectObject(id: string, name: string) {
    selectedId = id;
    onSelectionChange({ id, name });
  }

  function clearSelection() {
    selectedId = undefined;
    onSelectionChange(undefined);
  }

  function addNode(kind: AssetKind, position: GraphPoint) {
    const node = createFixtureNode(kind, position, nodes);
    nodes = [...nodes, node];
    selectObject(node.id, node.name);
  }

  function handleBlankCanvasClick(event: MouseEvent) {
    if (isGraphInteractive(event.target) || drag) return;
    if (didPan) {
      didPan = false;
      return;
    }

    if (placementKind) {
      addNode(placementKind, graphPosition(event));
      onPlacementConsumed();
      return;
    }

    if (tool === "connect") connectionSourceId = undefined;
    clearSelection();
  }

  function handleNodeClick(node: CanvasNodeData, event: MouseEvent) {
    event.stopPropagation();
    if (suppressNodeClick) {
      suppressNodeClick = false;
      return;
    }

    if (tool !== "connect") {
      selectObject(node.id, node.name);
      return;
    }

    if (!connectionSourceId) {
      connectionSourceId = node.id;
      selectObject(node.id, node.name);
      return;
    }

    if (connectionSourceId === node.id) return;
    if (
      edges.some(
        (edge) =>
          edge.sourceId === connectionSourceId && edge.targetId === node.id,
      )
    )
      return;

    const source = nodes.find(
      (candidate) => candidate.id === connectionSourceId,
    );
    if (!source) return;

    let edgeId = `${connectionSourceId}-${node.id}`;
    let suffix = 2;
    while (edges.some((edge) => edge.id === edgeId))
      edgeId = `${connectionSourceId}-${node.id}-${suffix++}`;

    edges = [
      ...edges,
      {
        id: edgeId,
        sourceId: connectionSourceId,
        targetId: node.id,
        relationshipLabel: "TRUST",
        visualStyle: "trust",
      },
    ];
    selectObject(edgeId, `${source.name} → ${node.name}`);
    connectionSourceId = undefined;
    onEdgeCreated();
  }

  function handleEdgeClick(edge: CanvasEdgeData, event: MouseEvent) {
    event.stopPropagation();
    const source = nodes.find((node) => node.id === edge.sourceId);
    const target = nodes.find((node) => node.id === edge.targetId);
    selectObject(
      edge.id,
      source && target ? `${source.name} → ${target.name}` : edge.id,
    );
  }

  function handleContextMenu(event: MouseEvent) {
    contextGraphPosition = graphPosition(event);
  }

  function handleKeydown(event: KeyboardEvent) {
    switch (event.key) {
      case "Escape":
        connectionSourceId = undefined;
        break;
      case "ArrowUp":
        event.preventDefault();
        panBy(0, PAN_STEP);
        break;
      case "ArrowDown":
        event.preventDefault();
        panBy(0, -PAN_STEP);
        break;
      case "ArrowLeft":
        event.preventDefault();
        panBy(PAN_STEP, 0);
        break;
      case "ArrowRight":
        event.preventDefault();
        panBy(-PAN_STEP, 0);
        break;
      case "+":
      case "=":
        event.preventDefault();
        setZoom(zoom + ZOOM_STEP);
        break;
      case "-":
        event.preventDefault();
        setZoom(zoom - ZOOM_STEP);
        break;
      case "0":
        event.preventDefault();
        resetView();
        break;
    }
  }
</script>

<section class="canvas-shell" aria-label="Network topology canvas">
  <ContextMenu.Root>
    <ContextMenu.Trigger class="canvas-context-menu-trigger">
      <!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions (intentionally focusable, keyboard-operated custom canvas with separate interactive SVG graph controls) -->
      <div
        class="canvas-surface"
        role="application"
        tabindex="0"
        aria-label="Network topology canvas. Drag blank space to pan or drag nodes to reposition them. Right-click to open viewport actions. Use the mouse wheel or keyboard to zoom."
        style:--grid-offset-x={`${pan.x}px`}
        style:--grid-offset-y={`${pan.y}px`}
        style:--minor-grid-size={`${gridSize}px`}
        style:--major-grid-size={`${gridSize * 5}px`}
        bind:clientWidth={viewport.width}
        bind:clientHeight={viewport.height}
        onpointerdown={handlePointerDown}
        onpointermove={handlePointerMove}
        onpointerup={handlePointerUp}
        onpointercancel={cancelPan}
        onwheel={handleWheel}
        onclick={handleBlankCanvasClick}
        oncontextmenu={handleContextMenu}
        onkeydown={handleKeydown}
      >
        <svg
          class="canvas-graph"
          viewBox={`0 0 ${viewport.width} ${viewport.height}`}
          aria-label="Network graph"
        >
          <defs>
            <marker
              id={canvasPreviewArrowId}
              markerWidth="8"
              markerHeight="8"
              refX="7"
              refY="3"
              orient="auto"
            >
              <path class="canvas-preview-arrow" d="M0 0 8 3 0 6Z" />
            </marker>
          </defs>
          <g transform={worldTransform}>
            {#each edges as edge (edge.id)}
              {@const source = nodes.find((node) => node.id === edge.sourceId)}
              {@const target = nodes.find((node) => node.id === edge.targetId)}
              {#if source && target}
                <CanvasEdge
                  {edge}
                  {source}
                  {target}
                  selected={selectedId === edge.id}
                  onclick={(event) => handleEdgeClick(edge, event)}
                />
              {/if}
            {/each}
            {#if tool === "connect" && connectionSource && pointerGraphPosition}
              {@const sourcePosition = nodeCenter(connectionSource)}
              <path
                class="canvas-preview-edge"
                d={`M ${sourcePosition.x} ${sourcePosition.y} L ${pointerGraphPosition.x} ${pointerGraphPosition.y}`}
                marker-end={`url(#${canvasPreviewArrowId})`}
              />
            {/if}
            {#each nodes as node (node.id)}
              <CanvasNode
                {node}
                selected={selectedId === node.id}
                source={connectionSourceId === node.id}
                dragging={nodeDrag?.nodeId === node.id}
                onpointerdown={(event) => startNodeDrag(node, event)}
                onclick={(event) => handleNodeClick(node, event)}
              />
            {/each}
          </g>
        </svg>
      </div>
    </ContextMenu.Trigger>
    <ContextMenu.Portal>
      <ContextMenu.Content
        class="dashboard-menu-content"
        sideOffset={6}
        aria-label="Viewport actions"
      >
        <ContextMenu.Item
          class="dashboard-menu-item"
          onclick={() => setZoom(zoom + ZOOM_STEP)}>Zoom in</ContextMenu.Item
        >
        <ContextMenu.Item
          class="dashboard-menu-item"
          onclick={() => setZoom(zoom - ZOOM_STEP)}>Zoom out</ContextMenu.Item
        >
        <ContextMenu.Item class="dashboard-menu-item" onclick={resetView}
          >Reset view</ContextMenu.Item
        >
        <ContextMenu.Separator class="canvas-menu-separator" />
        <ContextMenu.Item
          class="dashboard-menu-item"
          onclick={() => addNode("Server", contextGraphPosition)}
          >Add server here</ContextMenu.Item
        >
      </ContextMenu.Content>
    </ContextMenu.Portal>
  </ContextMenu.Root>

  <p class="canvas-hint">
    Drag blank space to pan. Right-click to open actions. Scroll or use the
    controls to zoom.
  </p>
  <div class="canvas-controls" aria-label="Canvas zoom controls">
    <button
      type="button"
      aria-label="Zoom out"
      onclick={() => setZoom(zoom - ZOOM_STEP)}>−</button
    >
    <output aria-live="polite" aria-atomic="true">{zoom}%</output>
    <button
      type="button"
      aria-label="Zoom in"
      onclick={() => setZoom(zoom + ZOOM_STEP)}>+</button
    >
    <button type="button" class="canvas-reset" onclick={resetView}>Reset</button
    >
  </div>
</section>

<style>
  .canvas-shell {
    position: relative;
    height: 100%;
    min-height: 0;
    overflow: hidden;
    background: var(--ds-color-canvas);
  }
  :global(.canvas-context-menu-trigger) {
    display: block;
    height: 100%;
  }
  .canvas-surface {
    width: 100%;
    height: 100%;
    touch-action: none;
    cursor: grab;
    outline: 0;
    background-color: var(--ds-color-canvas);
    background-image:
      linear-gradient(#cbd3dd55 1px, transparent 1px),
      linear-gradient(90deg, #cbd3dd55 1px, transparent 1px),
      linear-gradient(#b6c1ce44 1px, transparent 1px),
      linear-gradient(90deg, #b6c1ce44 1px, transparent 1px);
    background-position:
      var(--grid-offset-x) var(--grid-offset-y),
      var(--grid-offset-x) var(--grid-offset-y),
      var(--grid-offset-x) var(--grid-offset-y),
      var(--grid-offset-x) var(--grid-offset-y);
    background-size:
      var(--minor-grid-size) var(--minor-grid-size),
      var(--minor-grid-size) var(--minor-grid-size),
      var(--major-grid-size) var(--major-grid-size),
      var(--major-grid-size) var(--major-grid-size);
    transition: background-size 120ms ease-out;
  }
  .canvas-surface:active {
    cursor: grabbing;
  }
  .canvas-surface:focus-visible {
    outline: 2px solid var(--ds-color-focus);
    outline-offset: -2px;
  }
  .canvas-graph {
    display: block;
    width: 100%;
    height: 100%;
    overflow: visible;
  }
  .canvas-preview-edge {
    fill: none;
    stroke: #c77a19;
    stroke-width: 2;
    stroke-dasharray: 6 4;
    pointer-events: none;
  }
  .canvas-preview-arrow {
    fill: #c77a19;
  }
  .canvas-hint,
  .canvas-controls {
    position: absolute;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-md);
  }
  .canvas-hint {
    left: var(--ds-space-3);
    bottom: var(--ds-space-3);
    margin: 0;
    padding: 0.3125rem var(--ds-space-2);
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-xs);
  }
  .canvas-controls {
    right: var(--ds-space-3);
    bottom: var(--ds-space-3);
    display: flex;
    align-items: stretch;
    overflow: hidden;
  }
  .canvas-controls button,
  .canvas-controls output {
    min-width: 2.75rem;
    min-height: 2.75rem;
    border: 0;
    background: transparent;
    color: var(--ds-color-text);
    font: inherit;
  }
  .canvas-controls button {
    display: grid;
    place-items: center;
    font-size: 1.25rem;
  }
  .canvas-controls button:hover {
    background: var(--ds-color-accent-soft);
  }
  .canvas-controls output {
    display: grid;
    place-items: center;
    border-inline: 1px solid var(--ds-color-border-soft);
    font-family: var(--ds-font-mono);
    font-variant-numeric: tabular-nums;
  }
  .canvas-controls .canvas-reset {
    width: auto;
    padding-inline: var(--ds-space-2);
    border-left: 1px solid var(--ds-color-border-soft);
    font-size: var(--ds-text-sm);
  }
  :global(.canvas-menu-separator) {
    height: 1px;
    margin: 0.25rem 0;
    background: var(--ds-color-border-soft);
  }
  @media (max-width: 35rem) {
    .canvas-hint {
      max-width: calc(100% - 8rem);
    }
    .canvas-controls {
      right: var(--ds-space-2);
      bottom: var(--ds-space-2);
    }
    .canvas-hint {
      left: var(--ds-space-2);
      bottom: var(--ds-space-2);
    }
    .canvas-controls .canvas-reset {
      display: none;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .canvas-surface {
      transition: none;
    }
  }
  @media (forced-colors: active) {
    .canvas-surface {
      forced-color-adjust: auto;
      background-color: Canvas;
      background-image:
        linear-gradient(CanvasText 1px, transparent 1px),
        linear-gradient(90deg, CanvasText 1px, transparent 1px);
      background-position:
        var(--grid-offset-x) var(--grid-offset-y),
        var(--grid-offset-x) var(--grid-offset-y);
      background-size:
        var(--major-grid-size) var(--major-grid-size),
        var(--major-grid-size) var(--major-grid-size);
    }
    .canvas-hint,
    .canvas-controls {
      border-color: CanvasText;
      background: Canvas;
      color: CanvasText;
    }
    .canvas-controls output,
    .canvas-controls .canvas-reset {
      border-color: CanvasText;
    }
  }
</style>
