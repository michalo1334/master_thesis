<script lang="ts">
  import { ContextMenu } from "bits-ui";
  import CanvasEdge from "./canvas/CanvasEdge.svelte";
  import CanvasNode from "./canvas/CanvasNode.svelte";
  import { nodeCenter } from "./canvas/geometry";
  import type {
    GraphNode,
    GraphPoint,
    TopologyDocument,
    TopologyEditorState,
  } from "./model";
  import { createNetworkReachabilityEdge, type GraphEdge } from "./model";

  const MIN_ZOOM = 25;
  const MAX_ZOOM = 200;
  const ZOOM_STEP = 10;
  const PAN_STEP = 40;
  const DRAG_THRESHOLD = 4;

  interface Props {
    graph: TopologyDocument["graph"];
    editor: TopologyEditorState;
    onGraphChange: (graph: TopologyDocument["graph"]) => void;
    onEditorChange: (editor: TopologyEditorState) => void;
  }

  let { graph, editor, onGraphChange, onEditorChange }: Props = $props();
  const canvasPreviewArrowId = $props.id();
  let viewport = $state({ width: 0, height: 0 });
  let pointerGraphPosition = $state<GraphPoint>();
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
  let gridSize = $derived(20 * (editor.zoom / 100));
  let worldTransform = $derived(
    `translate(${editor.pan.x} ${editor.pan.y}) scale(${editor.zoom / 100})`,
  );
  let connectionSource = $derived(
    graph.nodes.find((node) => node.id === editor.connectionSourceId),
  );

  function nodePosition(node: GraphNode): GraphPoint {
    return { x: node.viewData.x_pos, y: node.viewData.y_pos };
  }

  function updateEditor(change: Partial<TopologyEditorState>) {
    onEditorChange({ ...editor, ...change });
  }

  function updateGraph(change: Partial<TopologyDocument["graph"]>) {
    onGraphChange({ ...graph, ...change });
  }

  function clampZoom(value: number) {
    return Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, value));
  }

  function setZoom(zoom: number) {
    updateEditor({ zoom: clampZoom(zoom) });
  }

  function panBy(x: number, y: number) {
    updateEditor({ pan: { x: editor.pan.x + x, y: editor.pan.y + y } });
  }

  function resetView() {
    updateEditor({ zoom: 100, pan: { x: 0, y: 0 } });
  }

  function graphPosition(event: PointerEvent | MouseEvent): GraphPoint {
    const surface = event.currentTarget as HTMLElement;
    const bounds = surface.getBoundingClientRect();
    const scale = editor.zoom / 100;
    return {
      x: (event.clientX - bounds.left - editor.pan.x) / scale,
      y: (event.clientY - bounds.top - editor.pan.y) / scale,
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
      panX: editor.pan.x,
      panY: editor.pan.y,
    };
  }

  function startNodeDrag(node: GraphNode, event: PointerEvent) {
    if (event.button !== 0 || !event.isPrimary) return;

    event.stopPropagation();
    const element = event.currentTarget as SVGGElement;
    element.setPointerCapture(event.pointerId);
    const position = nodePosition(node);
    nodeDrag = {
      pointerId: event.pointerId,
      nodeId: node.id,
      startX: event.clientX,
      startY: event.clientY,
      nodeX: position.x,
      nodeY: position.y,
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

      const scale = editor.zoom / 100;
      updateGraph({
        nodes: graph.nodes.map((node) =>
          node.id === nodeDrag?.nodeId
            ? {
                ...node,
                viewData: {
                  ...node.viewData,
                  x_pos: nodeDrag.nodeX + deltaX / scale,
                  y_pos: nodeDrag.nodeY + deltaY / scale,
                },
              }
            : node,
        ),
      });
      return;
    }
    if (!drag || drag.pointerId !== event.pointerId) return;

    didPan ||= event.clientX !== drag.startX || event.clientY !== drag.startY;
    updateEditor({
      pan: {
        x: drag.panX + event.clientX - drag.startX,
        y: drag.panY + event.clientY - drag.startY,
      },
    });
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
    if (nodeDrag?.pointerId === event.pointerId) return endNodeDrag(event);
    if (!drag || drag.pointerId !== event.pointerId) return;
    releasePointer(event);
    drag = undefined;
  }

  function cancelPan(event: PointerEvent) {
    if (nodeDrag?.pointerId === event.pointerId) return endNodeDrag(event);
    releasePointer(event);
    drag = undefined;
  }

  function handleWheel(event: WheelEvent) {
    event.preventDefault();
    setZoom(editor.zoom + (event.deltaY < 0 ? ZOOM_STEP : -ZOOM_STEP));
  }

  function selectObject(id: string) {
    updateEditor({ selectedId: id });
  }

  function handleBlankCanvasClick(event: MouseEvent) {
    if (isGraphInteractive(event.target) || drag) return;
    if (didPan) {
      didPan = false;
      return;
    }
    updateEditor({
      selectedId: undefined,
      connectionSourceId:
        editor.tool === "connect" ? undefined : editor.connectionSourceId,
    });
  }

  function handleNodeClick(node: GraphNode, event: MouseEvent) {
    event.stopPropagation();
    if (suppressNodeClick) {
      suppressNodeClick = false;
      return;
    }
    if (editor.tool !== "connect") return selectObject(node.id);
    if (!editor.connectionSourceId) {
      updateEditor({ connectionSourceId: node.id, selectedId: node.id });
      return;
    }
    if (editor.connectionSourceId === node.id) return;
    if (
      graph.edges.some(
        (edge) =>
          edge.fromId === editor.connectionSourceId && edge.toId === node.id,
      )
    )
      return;

    const source = graph.nodes.find(
      (candidate) => candidate.id === editor.connectionSourceId,
    );
    const target = graph.nodes.find((candidate) => candidate.id === node.id);
    if (!source || !target) return;
    const edge = createNetworkReachabilityEdge(graph.id, source.id, target.id);
    updateGraph({ edges: [...graph.edges, edge] });
    updateEditor({
      selectedId: edge.id,
      connectionSourceId: undefined,
      tool: "select",
    });
  }

  function handleEdgeClick(edge: GraphEdge, event: MouseEvent) {
    event.stopPropagation();
    selectObject(edge.id);
  }

  function handleKeydown(event: KeyboardEvent) {
    switch (event.key) {
      case "Escape":
        updateEditor({ connectionSourceId: undefined });
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
        setZoom(editor.zoom + ZOOM_STEP);
        break;
      case "-":
        event.preventDefault();
        setZoom(editor.zoom - ZOOM_STEP);
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
        style:--grid-offset-x={`${editor.pan.x}px`}
        style:--grid-offset-y={`${editor.pan.y}px`}
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
                (node) => node.id === edge.fromId,
              )}
              {@const target = graph.nodes.find(
                (node) => node.id === edge.toId,
              )}
              {#if source && target}<CanvasEdge
                  {edge}
                  {source}
                  {target}
                  sourcePosition={nodePosition(source)}
                  targetPosition={nodePosition(target)}
                  selected={editor.selectedId === edge.id}
                  onclick={(event) => handleEdgeClick(edge, event)}
                />{/if}
            {/each}
            {#if editor.tool === "connect" && connectionSource && pointerGraphPosition}
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
                selected={editor.selectedId === node.id}
                source={editor.connectionSourceId === node.id}
                dragging={nodeDrag?.nodeId === node.id}
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
          onclick={() => setZoom(editor.zoom + ZOOM_STEP)}
          >Zoom in</ContextMenu.Item
        >
        <ContextMenu.Item
          class="dashboard-menu-item"
          onclick={() => setZoom(editor.zoom - ZOOM_STEP)}
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
      onclick={() => setZoom(editor.zoom - ZOOM_STEP)}>−</button
    ><output aria-live="polite" aria-atomic="true">{editor.zoom}%</output
    ><button
      type="button"
      aria-label="Zoom in"
      onclick={() => setZoom(editor.zoom + ZOOM_STEP)}>+</button
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
