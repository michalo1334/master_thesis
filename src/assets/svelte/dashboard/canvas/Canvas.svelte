<script lang="ts">
  import { ContextMenu } from "bits-ui";
  import CanvasEdge from "./CanvasEdge.svelte";
  import CanvasNode from "./CanvasNode.svelte";
  import { nodeCenter } from "./geometry";
  import type { Edge, LoadedGraph, Node } from "../contract";
  import {
    type DragState,
    type NodeDragState,
    type CanvasState,
    type Point,
  } from "./canvasState";
  import type { CanvasSelection } from "../workspace/CanvasDocument.svelte";

  const MIN_ZOOM = 25;
  const MAX_ZOOM = 200;
  const ZOOM_STEP = 10;
  const PAN_STEP = 40;
  const DRAG_THRESHOLD = 4;

  interface Props {
    graph: LoadedGraph;
    selection: CanvasSelection;
    onGraphChange: (graph: LoadedGraph) => void;
    onSelectionChange: (selection: CanvasSelection) => void;
  }

  let { graph, selection, onGraphChange, onSelectionChange }: Props = $props();
  const canvasPreviewArrowId = $props.id();
  let viewport = $state({ width: 0, height: 0 });
  let pointerGraphPosition = $state<Point>();
  let didPan = $state(false);
  let suppressNodeClick = $state(false);

  let canvasState = $state<CanvasState>({
    connectMode: false,
    zoom: 100,
    pan: { x: 0, y: 0 },
    connectionSourceId: undefined,
  });
  let dragState = $state<DragState>();
  let nodeDragState = $state<NodeDragState>();

  let gridSize = $derived(20 * (canvasState.zoom / 100));
  let worldTransform = $derived(
    `translate(${canvasState.pan.x} ${canvasState.pan.y}) scale(${canvasState.zoom / 100})`,
  );
  let connectionSource = $derived(
    graph.nodes.find((node) => node.id === canvasState.connectionSourceId),
  );

  function nodePosition(node: Node): Point {
    return { x: node.view_data.x_pos, y: node.view_data.y_pos };
  }

  function updateCanvasState(change: Partial<CanvasState>) {
    Object.assign(canvasState, change);
  }

  function updateGraph(change: Partial<LoadedGraph>) {
    onGraphChange({ ...graph, ...change });
  }

  function clampZoom(value: number) {
    return Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, value));
  }

  function setZoom(zoom: number) {
    updateCanvasState({ zoom: clampZoom(zoom) });
  }

  function panBy(x: number, y: number) {
    updateCanvasState({
      pan: { x: canvasState.pan.x + x, y: canvasState.pan.y + y },
    });
  }

  function resetView() {
    updateCanvasState({ zoom: 100, pan: { x: 0, y: 0 } });
  }

  function graphPosition(event: PointerEvent | MouseEvent): Point {
    const surface = event.currentTarget as HTMLElement;
    const bounds = surface.getBoundingClientRect();
    const scale = canvasState.zoom / 100;
    return {
      x: (event.clientX - bounds.left - canvasState.pan.x) / scale,
      y: (event.clientY - bounds.top - canvasState.pan.y) / scale,
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
    dragState = {
      pointerId: event.pointerId,
      start: { x: event.clientX, y: event.clientY },
      pan: canvasState.pan,
    };
  }

  function startNodeDrag(node: Node, event: PointerEvent) {
    if (event.button !== 0 || !event.isPrimary) return;

    event.stopPropagation();
    const element = event.currentTarget as SVGGElement;
    element.setPointerCapture(event.pointerId);
    const position = nodePosition(node);
    nodeDragState = {
      pointerId: event.pointerId,
      nodeId: node.id,
      start: { x: event.clientX, y: event.clientY },
      nodePos: { x: position.x, y: position.y },
      moved: false,
      element,
    };
  }

  function handlePointerMove(event: PointerEvent) {
    pointerGraphPosition = graphPosition(event);
    if (nodeDragState?.pointerId === event.pointerId) {
      const deltaX = event.clientX - nodeDragState.start.x;
      const deltaY = event.clientY - nodeDragState.start.y;
      if (!nodeDragState.moved && Math.hypot(deltaX, deltaY) >= DRAG_THRESHOLD)
        nodeDragState.moved = true;
      if (!nodeDragState.moved) return;

      const scale = canvasState.zoom / 100;
      updateGraph({
        nodes: graph.nodes.map((node) =>
          node.id === nodeDragState?.nodeId
            ? {
                ...node,
                view_data: {
                  ...node.view_data,
                  x_pos: nodeDragState.nodePos.x + deltaX / scale,
                  y_pos: nodeDragState.nodePos.y + deltaY / scale,
                },
              }
            : node,
        ),
      });
      return;
    }
    if (!dragState || dragState.pointerId !== event.pointerId) return;

    didPan ||=
      event.clientX !== dragState.start.x ||
      event.clientY !== dragState.start.y;
    updateCanvasState({
      pan: {
        x: dragState.pan.x + event.clientX - dragState.start.x,
        y: dragState.pan.y + event.clientY - dragState.start.y,
      },
    });
  }

  function releasePointer(event: PointerEvent) {
    if (!dragState || dragState.pointerId !== event.pointerId) return;
    const surface = event.currentTarget as HTMLDivElement;
    if (surface.hasPointerCapture(event.pointerId))
      surface.releasePointerCapture(event.pointerId);
  }

  function endNodeDrag(event: PointerEvent) {
    if (!nodeDragState || nodeDragState.pointerId !== event.pointerId) return;
    if (nodeDragState.element.hasPointerCapture(event.pointerId))
      nodeDragState.element.releasePointerCapture(event.pointerId);
    if (event.type === "pointerup" && nodeDragState.moved)
      suppressNodeClick = true;
    nodeDragState = undefined;
  }

  function handlePointerUp(event: PointerEvent) {
    if (nodeDragState?.pointerId === event.pointerId) return endNodeDrag(event);
    if (!dragState || dragState.pointerId !== event.pointerId) return;
    releasePointer(event);
    dragState = undefined;
  }

  function cancelPan(event: PointerEvent) {
    if (nodeDragState?.pointerId === event.pointerId) return endNodeDrag(event);
    releasePointer(event);
    dragState = undefined;
  }

  function handleWheel(event: WheelEvent) {
    event.preventDefault();
    setZoom(canvasState.zoom + (event.deltaY < 0 ? ZOOM_STEP : -ZOOM_STEP));
  }

  function handleBlankCanvasClick(_event: MouseEvent) {
    onSelectionChange({ kind: "none" });
  }

  function handleNodeClick(node: Node, event: MouseEvent) {
    event.stopPropagation();
    if (suppressNodeClick) {
      suppressNodeClick = false;
      return;
    }
    onSelectionChange({ kind: "node", nodeId: node.id });
  }

  function handleEdgeClick(edge: Edge, event: MouseEvent) {
    event.stopPropagation();
    onSelectionChange({ kind: "edge", edgeId: edge.id });
  }

  function handleKeydown(event: KeyboardEvent) {
    switch (event.key) {
      case "Escape":
        updateCanvasState({ connectionSourceId: undefined });
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
        setZoom(canvasState.zoom + ZOOM_STEP);
        break;
      case "-":
        event.preventDefault();
        setZoom(canvasState.zoom - ZOOM_STEP);
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
      <!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
      <div
        class="canvas-surface"
        role="application"
        tabindex="0"
        aria-label="Network topology canvas. Drag blank space to pan or drag nodes to reposition them. Right-click to open viewport actions. Use the mouse wheel or keyboard to zoom."
        style:--grid-offset-x={`${canvasState.pan.x}px`}
        style:--grid-offset-y={`${canvasState.pan.y}px`}
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
        onkeydown={handleKeydown}
      >
        <svg
          class="canvas-graph"
          viewBox={`0 0 ${viewport.width} ${viewport.height}`}
          aria-label="Network graph"
        >
          <defs
            ><marker
              id={canvasPreviewArrowId}
              markerWidth="8"
              markerHeight="8"
              refX="7"
              refY="3"
              orient="auto"
              ><path class="canvas-preview-arrow" d="M0 0 8 3 0 6Z" /></marker
            ></defs
          >
          <g transform={worldTransform}>
            {#each graph.edges as edge (edge.id)}
              {@const source = graph.nodes.find(
                (node) => node.id === edge.from_id,
              )}
              {@const target = graph.nodes.find(
                (node) => node.id === edge.to_id,
              )}
              {#if source && target}<CanvasEdge
                  {edge}
                  {source}
                  {target}
                  sourcePosition={nodePosition(source)}
                  targetPosition={nodePosition(target)}
                  selected={selection.kind === "edge" &&
                    selection.edgeId === edge.id}
                  onclick={(event) => handleEdgeClick(edge, event)}
                />{/if}
            {/each}
            {#if canvasState.connectMode && connectionSource && pointerGraphPosition}
              {@const sourcePosition = nodeCenter(
                nodePosition(connectionSource),
              )}
              <path
                class="canvas-preview-edge"
                d={`M ${sourcePosition.x} ${sourcePosition.y} L ${pointerGraphPosition.x} ${pointerGraphPosition.y}`}
                marker-end={`url(#${canvasPreviewArrowId})`}
              />
            {/if}
            {#each graph.nodes as node (node.id)}
              <CanvasNode
                {node}
                position={nodePosition(node)}
                selected={selection.kind === "node" &&
                  selection.nodeId === node.id}
                source={canvasState.connectionSourceId === node.id}
                dragging={nodeDragState?.nodeId === node.id}
                onpointerdown={(event) => startNodeDrag(node, event)}
                onclick={(event) => handleNodeClick(node, event)}
              />
            {/each}
          </g>
        </svg>
      </div>
    </ContextMenu.Trigger>
    <ContextMenu.Portal
      ><ContextMenu.Content
        class="dashboard-menu-content"
        sideOffset={6}
        aria-label="Viewport actions"
      >
        <ContextMenu.Item
          class="dashboard-menu-item"
          onclick={() => setZoom(canvasState.zoom + ZOOM_STEP)}
          >Zoom in</ContextMenu.Item
        >
        <ContextMenu.Item
          class="dashboard-menu-item"
          onclick={() => setZoom(canvasState.zoom - ZOOM_STEP)}
          >Zoom out</ContextMenu.Item
        >
        <ContextMenu.Item class="dashboard-menu-item" onclick={resetView}
          >Reset view</ContextMenu.Item
        >
      </ContextMenu.Content></ContextMenu.Portal
    >
  </ContextMenu.Root>
  <p class="canvas-hint">
    Drag blank space to pan. Right-click to open actions. Scroll or use the
    controls to zoom.
  </p>
  <div class="canvas-controls" aria-label="Canvas zoom controls">
    <button
      type="button"
      aria-label="Zoom out"
      onclick={() => setZoom(canvasState.zoom - ZOOM_STEP)}>−</button
    ><output aria-live="polite" aria-atomic="true">{canvasState.zoom}%</output
    ><button
      type="button"
      aria-label="Zoom in"
      onclick={() => setZoom(canvasState.zoom + ZOOM_STEP)}>+</button
    ><button type="button" class="canvas-reset" onclick={resetView}
      >Reset</button
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
      linear-gradient(
        color-mix(in srgb, var(--ds-color-border) 33%, transparent) 1px,
        transparent 1px
      ),
      linear-gradient(
        90deg,
        color-mix(in srgb, var(--ds-color-border) 33%, transparent) 1px,
        transparent 1px
      ),
      linear-gradient(
        color-mix(in srgb, var(--ds-color-border) 27%, transparent) 1px,
        transparent 1px
      ),
      linear-gradient(
        90deg,
        color-mix(in srgb, var(--ds-color-border) 27%, transparent) 1px,
        transparent 1px
      );
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
    stroke: var(--ds-color-preview-edge);
    stroke-width: 2;
    stroke-dasharray: 6 4;
    pointer-events: none;
  }
  .canvas-preview-arrow {
    fill: var(--ds-color-preview-edge);
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
  @media (max-width: 35rem) {
    .canvas-hint {
      max-width: calc(100% - 8rem);
      left: var(--ds-space-2);
      bottom: var(--ds-space-2);
    }
    .canvas-controls {
      right: var(--ds-space-2);
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
