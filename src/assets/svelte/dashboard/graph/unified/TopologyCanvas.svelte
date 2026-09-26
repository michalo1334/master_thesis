<script lang="ts">
  import type {
    Edge,
    GraphContract,
    Node,
  } from "../../../contracts.generated/graph";
  import type { TopologyProjection } from "../../../contracts.generated/dashboard/graph";

  import { ContextMenu } from "bits-ui";
  import { onDestroy, untrack } from "svelte";
  import CanvasNode from "../canvas/CanvasNode.svelte";
  import { edgePresentation, nodePresentation } from "../presentation/registry";
  import type {
    CanvasEdgeAppearance,
    CanvasNodeAppearance,
  } from "../canvas/appearance";
  import {
    clampZoom,
    formatWorldTransform,
    screenToWorld,
    ZOOM_STEP,
    type Point,
  } from "../canvas/canvasState";
  import {
    exceedsDragThreshold,
    pointerDelta,
    screenDeltaToWorld,
    translatePositionMap,
  } from "../canvas/pointer-math";
  import { NODE_WIDTH } from "../canvas/geometry";
  import { buildTopologyScene, topologyEntityLabel } from "../topology-scene";
  import { indexTopologyScene } from "../topology-scene-index";
  import {
    CONTEXT_SIZE,
    SEGMENT_HEADER_HEIGHT,
    SERVICE_SIZE,
    measureTopology,
  } from "./layout";
  import {
    buildConnectionBundles,
    buildOutgoingConnectionDetails,
    connectionDetailLabel,
    type TopologyConnectionBundle,
  } from "./topology-bundles";
  import {
    connectRects,
    fitRects,
    pointInRect,
    rectCenter,
    type Rect,
  } from "./canvas-geometry";
  import { buildTopologySpatialView } from "./canvas-spatial-view-model";
  import {
    buildContextLinks,
    buildDrawnEntityIds,
    buildStructuralLinks,
    indexRunsEdges,
  } from "./canvas-link-view-model";
  import {
    buildTopologyConnectionHandles,
    type TopologyConnectionHandleView,
  } from "./canvas-handle-view-model";
  import {
    initialDetailLevel,
    resolveDetailLevel,
    showsHosts,
    showsServices,
    showsStructuralEdges,
    type TopologyDetailLevel,
  } from "./semantic-zoom";
  import { computeTopologyLens } from "../topology-lens";
  import { unplacedReason, unplacedReasonCode } from "../topology-placement";
  import { TOPOLOGY_NODE_TYPES } from "./topology-node-types";

  export type TopologyProjectionStatus = "ready" | "pending" | "error";

  /**
   * Viewport command from a canvas control.
   *
   * The command changes viewport state or attached-context placement only.
   * It never requests a projection and never changes graph membership.
   */
  export interface TopologyViewCommand {
    kind: "fit" | "reset" | "focus";
    /** Entity to focus. Required for `kind: "focus"`. */
    entityId?: string;
    /** Monotonic token. A changed token runs the command once. */
    token: number;
  }

  /**
   * Add request from a canvas control.
   *
   * The canvas owns world coordinates, so it resolves the anchor position: the
   * last context position when one exists, otherwise the viewport center.
   */
  export interface TopologyAddRequest {
    type: Node["type"];
    /** Monotonic token. A changed token creates one node. */
    token: number;
  }

  interface Props {
    graph: GraphContract;
    projection: TopologyProjection;
    /** Presentation state of the accepted projection. */
    projectionStatus?: TopologyProjectionStatus;
    /** Source of the accepted projection. Draft flows are unsaved. */
    projectionSource?: "revision" | "draft";
    /** Entities added or changed after the accepted projection. */
    pendingEntityIds?: readonly string[];
    selectedNodeId?: string;
    selectedEdgeId?: string;
    readOnly?: boolean;
    /** Viewport command from a canvas control. */
    viewCommand?: TopologyViewCommand;
    /** Add request from a canvas control. */
    addRequest?: TopologyAddRequest;
    /**
     * Acknowledgement of a view command, so the caller can clear it.
     *
     * A command stays in caller state until the canvas runs it. Clearing it
     * keeps a later remount from running the same command twice.
     */
    onViewCommandHandled?: (token: number) => void;
    /** Acknowledgement of an add request, so the caller can clear it. */
    onAddRequestHandled?: (token: number) => void;
    /**
     * Fit a loaded graph once, when a non-zero viewport appears. Pass `false`
     * for a graph the user is still authoring. Defaults to `true`.
     */
    autoFit?: boolean;
    /** Entities whose adjacency lens stays visible after selection moves. */
    pinnedEntityIds?: readonly string[];
    onTogglePin?: (entityId: string) => void;
    onClearPins?: () => void;
    nodeAppearance?: (node: Node) => CanvasNodeAppearance | undefined;
    edgeAppearance?: (edge: Edge) => CanvasEdgeAppearance | undefined;
    /** Appearance of every segment-pair connection bundle. */
    bundleAppearance?: (
      bundle: TopologyConnectionBundle,
    ) => CanvasEdgeAppearance | undefined;
    onGeometryChange?: (positions: ReadonlyMap<string, Point>) => void;
    onSelectNode?: (nodeId: string) => void;
    onSelectEdge?: (edgeId: string) => void;
    onClearSelection?: () => void;
    onCreateConnection?: (
      sourceNodeId: string,
      targetNodeId: string | undefined,
      position: Point,
    ) => void;
    onAddNode?: (type: Node["type"], position: Point) => void;
    onDeleteSelection?: () => void;
    onCompareGraphs?: () => void;
    ariaLabel?: string;
  }

  let {
    graph,
    projection,
    projectionStatus = "ready",
    projectionSource = "revision",
    pendingEntityIds = [],
    selectedNodeId = undefined,
    selectedEdgeId = undefined,
    readOnly = false,
    viewCommand = undefined,
    addRequest = undefined,
    onViewCommandHandled = undefined,
    onAddRequestHandled = undefined,
    autoFit = true,
    pinnedEntityIds = [],
    onTogglePin = undefined,
    onClearPins = undefined,
    nodeAppearance = undefined,
    edgeAppearance = undefined,
    bundleAppearance = undefined,
    onGeometryChange = undefined,
    onSelectNode = undefined,
    onSelectEdge = undefined,
    onClearSelection = undefined,
    onCreateConnection = undefined,
    onAddNode = undefined,
    onDeleteSelection = undefined,
    onCompareGraphs = undefined,
    ariaLabel = "Topology canvas",
  }: Props = $props();

  const arrowMarkerId = $props.id();
  const INITIAL_ZOOM = 100;
  /** Largest zoom a focus command applies, so a small card keeps context. */
  const FOCUS_MAX_ZOOM = 150;
  /** World-space margin a focus command keeps around the focused entity. */
  const FOCUS_MARGIN = 160;
  const PAN_STEP = 40;
  /** Size of the square pin control, in world units. */
  const PIN_SIZE = 16;
  /** Extra right padding reserved for a pin control. */
  const PIN_LABEL_INSET = 22;
  /** Height of the compact host glyph used below near detail. */
  const HOST_GLYPH_HEIGHT = 32;
  /** Height of the unplaced card, which carries a label and a reason. */
  const UNPLACED_CARD_HEIGHT = 46;
  /** Viewport inset and bounded size for an anchored bundle detail. */
  const BUNDLE_POPOVER_MARGIN = 8;
  const BUNDLE_POPOVER_MAX_WIDTH = 16 * 16;
  const BUNDLE_POPOVER_MAX_HEIGHT = 12 * 16;
  /** Stable empty freeze, so a missing snapshot never invalidates the layout. */
  const NO_CONTEXT_FREEZE: ReadonlyMap<string, Point> = new Map();
  /** Segment width that leaves room for a CIDR next to the name. */
  const CIDR_MIN_WIDTH = 320;
  type PinnableKind = "segment" | "host" | "service" | "context" | "card";

  interface PinTarget {
    id: string;
    label: string;
    pinned: boolean;
    position: Point;
  }

  interface DragState {
    pointerId: number;
    ids: readonly string[];
    origins: Map<string, Point>;
    start: Point;
    moved: boolean;
    element: SVGGElement;
  }

  let surfaceElement: HTMLDivElement;
  let viewport = $state({ width: 0, height: 0 });
  let view = $state({ zoom: INITIAL_ZOOM, pan: { x: 0, y: 0 } as Point });
  let detail = $state<TopologyDetailLevel>(initialDetailLevel(INITIAL_ZOOM));
  let pointerPosition = $state<Point>();
  let contextPosition = $state<Point>();
  let suppressClick = $state(false);
  let panState = $state<{
    pointerId: number;
    start: Point;
    pan: Point;
  }>();
  let dragState = $state<DragState>();
  let connectionState = $state<{
    pointerId: number;
    sourceId: string;
    element: SVGCircleElement;
  }>();
  /**
   * Entity under DOM focus.
   *
   * Keyboard focus reveals the same adjacency lens as pointer selection, then
   * clears when focus leaves the canvas.
   */
  let keyboardFocusId = $state<string>();
  /** Connection source chosen from a connection handle by keyboard. */
  let keyboardConnection = $state<{ sourceId: string }>();
  /** Frozen context positions plus the snapshot they were taken from. */
  interface ContextFreeze {
    graphId: string;
    projection: TopologyProjection;
    positions: ReadonlyMap<string, Point>;
  }

  let graphIdentity = $derived(graph.id);
  let contextFreeze = $state.raw<ContextFreeze>();
  /**
   * Attached-context positions frozen by a geometry drag.
   *
   * Context keeps its world position while members move, and the ring search
   * does not run again. A new projection, a reloaded graph, or an explicit fit
   * ends the freeze.
   */
  let frozenContextPositions = $derived(
    contextFreeze &&
      contextFreeze.graphId === graphIdentity &&
      contextFreeze.projection === projection
      ? contextFreeze.positions
      : NO_CONTEXT_FREEZE,
  );
  let autoFittedGraphId = $state<string | undefined>();
  /** Latest drag sample, emitted at most once per animation frame. */
  let pendingGeometry: Map<string, Point> | undefined;
  let geometryFrame: number | undefined;

  let editable = $derived(!readOnly && Boolean(onGeometryChange));
  let worldTransform = $derived(formatWorldTransform(view));
  let gridSize = $derived(20 * (view.zoom / 100));
  let scene = $derived(
    buildTopologyScene(graph, projection, { pendingEntityIds }),
  );
  let layout = $derived(
    measureTopology(scene, { freezeContextPositions: frozenContextPositions }),
  );
  let sceneIndex = $derived(indexTopologyScene(scene));
  let nodeById = $derived(sceneIndex.nodesById);
  let pendingIds = $derived(new Set(pendingEntityIds));
  let placementIssueIds = $derived(
    new Set(
      scene.unplaced
        .filter((entry) => entry.status === "placement_issue")
        .map((entry) => entry.entityId),
    ),
  );
  let selfPolicyIds = $derived(
    new Set(
      scene.policyGroups
        .filter(
          (group) => group.group.from_segment_id === group.group.to_segment_id,
        )
        .map((group) => group.group.from_segment_id),
    ),
  );
  let pinnedIds = $derived(new Set(pinnedEntityIds));
  /**
   * Lens focus: the selection, the entity under DOM focus, and every pin.
   * Sorted pins keep the reveal independent of the order the user pinned.
   */
  let lensFocusIds = $derived.by(() => {
    const ids = [selectedNodeId, keyboardFocusId, ...[...pinnedIds].sort()];
    return [
      ...new Set(ids.filter((id): id is string => typeof id === "string")),
    ];
  });
  let lens = $derived(computeTopologyLens(graph, scene, lensFocusIds));
  /** Entity that starts a connection, whether a pointer or the keyboard began it. */
  let connectionSourceId = $derived(
    connectionState?.sourceId ?? keyboardConnection?.sourceId,
  );

  /**
   * Flat canvas geometry and member rows. The pure builder preserves projection
   * order while omitting members that the layout cannot place.
   */
  let spatialView = $derived(
    buildTopologySpatialView(scene, sceneIndex, layout, {
      serviceSize: SERVICE_SIZE,
      contextSize: CONTEXT_SIZE,
      unplacedCardHeight: UNPLACED_CARD_HEIGHT,
    }),
  );
  let nodeRects = $derived(spatialView.nodeRects);
  let entityRects = $derived(spatialView.entityRects);
  let hostViews = $derived(spatialView.hostViews);
  let unplacedFloaters = $derived(spatialView.unplacedFloaters);

  function pinnableKind(type: Node["type"]): PinnableKind {
    switch (type) {
      case "NetworkSegment":
        return "segment";
      case "Host":
        return "host";
      case "Service":
        return "service";
      case "Vulnerability":
      case "Credential":
      case "MissionCapability":
        return "context";
      default:
        return "card";
    }
  }

  /**
   * Top-left corner of the pin control for one entity.
   *
   * The control sits inside a segment header or a card, and just outside an
   * attached-context card, so it never covers the labels those entities draw.
   */
  function pinPosition(kind: PinnableKind, rect: Rect): Point {
    switch (kind) {
      case "segment":
        return {
          x: rect.x + rect.width - PIN_LABEL_INSET - PIN_SIZE,
          y: rect.y + 8,
        };
      case "context":
      case "card":
        return { x: rect.x + rect.width + 3, y: rect.y + 6 };
      default:
        return { x: rect.x + rect.width - PIN_SIZE - 8, y: rect.y + 6 };
    }
  }

  /** Pin controls for the selected and pinned entities that the canvas draws. */
  let pinTargets = $derived.by<PinTarget[]>(() => {
    if (!onTogglePin) return [];
    const ids = [
      ...new Set(
        [selectedNodeId, ...pinnedEntityIds].filter(
          (id): id is string => typeof id === "string",
        ),
      ),
    ];
    const targets: PinTarget[] = [];
    const floaters = new Set(
      unplacedFloaters.map((floater) => floater.node.id),
    );
    for (const id of ids) {
      const node = nodeById.get(id);
      const rect = entityRects.get(id);
      if (!node || !rect) continue;
      const kind: PinnableKind = floaters.has(id)
        ? "card"
        : pinnableKind(node.type);
      targets.push({
        id,
        label: entityLabel(node),
        pinned: pinnedIds.has(id),
        position: pinPosition(kind, rect),
      });
    }
    return targets;
  });

  let pinTargetIds = $derived(new Set(pinTargets.map((target) => target.id)));
  /** Pin controls by entity id, for placement beside each entity. */
  let pinTargetById = $derived(
    new Map(pinTargets.map((target) => [target.id, target])),
  );

  /** Accessible name of the entity a connection currently starts from. */
  let connectionSourceLabel = $derived.by(() => {
    const id = connectionSourceId;
    const node = id ? nodeById.get(id) : undefined;
    return node ? `${node.type} ${entityLabel(node)}` : "";
  });

  /**
   * Connection handles for hosts and services.
   *
   * Each handle is a sibling of its card, never a child of the card button, so
   * an assistive technology sees two separate controls. The handle exposes the
   * same connection path to pointer and keyboard.
   */
  let connectionHandles = $derived(
    editable && onCreateConnection
      ? buildTopologyConnectionHandles(hostViews, {
          detail,
          revealsHost,
          revealsService,
          serviceSize: SERVICE_SIZE,
          hostGlyphHeight: HOST_GLYPH_HEIGHT,
        })
      : [],
  );

  /** Connection handles by entity id, for placement beside each entity. */
  let connectionHandleById = $derived(
    new Map(connectionHandles.map((handle) => [handle.node.id, handle])),
  );

  function isDimmed(entityId: string): boolean {
    return lens.active && !lens.visibleIds.has(entityId);
  }

  function isPinned(entityId: string): boolean {
    return pinnedIds.has(entityId);
  }

  /** Hosts and services the lens reveals above the current zoom baseline. */
  function revealsHost(entityId: string): boolean {
    return showsHosts(detail) || lens.visibleIds.has(entityId);
  }

  function revealsService(entityId: string): boolean {
    return showsServices(detail) || lens.visibleIds.has(entityId);
  }

  /**
   * Attached context follows the UX baseline: it appears only through the lens,
   * when the entity is selected, keyboard-focused, or pinned. Zoom alone never
   * reveals it at any detail level.
   */
  function revealsContext(entityId: string): boolean {
    return lens.visibleIds.has(entityId);
  }

  /** Right inset of a label that shares its row with a pin control. */
  function labelInset(entityId: string, base: number): number {
    return pinTargetIds.has(entityId) ? base + PIN_LABEL_INSET : base;
  }

  /** One directed segment-pair connection bundle stays visible at every zoom. */
  let showsBundles = $derived(true);

  interface BundleView {
    key: string;
    bundle: TopologyConnectionBundle;
    path: { source: Point; target: Point };
    /** Visible connection count. */
    count: string;
    /** Accessible name: direction, connection count, and service summary. */
    label: string;
    /** Popover heading. */
    title: string;
    appearance: CanvasEdgeAppearance | undefined;
    dimmed: boolean;
    selected: boolean;
  }

  /**
   * Bundle disclosure state.
   *
   * Pointer hover, keyboard focus, and click each open one popover. Escape
   * closes it. The state lives in the view only and is never persisted.
   */
  let hoveredBundleKey = $state<string>();
  let focusedBundleKey = $state<string>();
  let openedBundleKey = $state<string>();
  let bundlePopoverKey = $derived(
    hoveredBundleKey ?? focusedBundleKey ?? openedBundleKey,
  );

  let bundleViews = $derived.by<BundleView[]>(() => {
    const views: BundleView[] = [];
    if (!showsBundles) return views;
    for (const bundle of buildConnectionBundles(scene)) {
      if (bundle.isSelf) continue;
      const from = nodeRects.get(bundle.fromSegmentId);
      const to = nodeRects.get(bundle.toSegmentId);
      if (!from || !to) continue;
      const fromName = segmentName(bundle.fromSegmentId);
      const toName = segmentName(bundle.toSegmentId);
      views.push({
        key: bundle.key,
        bundle,
        path: connectRects(from, to),
        count: String(bundle.connectionCount),
        label: `${fromName} to ${toName}, ${countLabel(
          bundle.connectionCount,
          "connection",
          "connections",
        )}, ${connectionSummary(bundle)}`,
        title: `${fromName} → ${toName}`,
        appearance: bundleAppearance?.(bundle),
        dimmed:
          lens.active &&
          !lens.visibleIds.has(bundle.fromSegmentId) &&
          !lens.visibleIds.has(bundle.toSegmentId),
        selected: Boolean(
          selectedEdgeId && bundle.policyEdgeIds.includes(selectedEdgeId),
        ),
      });
    }
    return views;
  });

  /** CSS-pixel position of a world point inside the surface. */
  function worldToScreen(point: Point): Point {
    const scale = view.zoom / 100;
    return {
      x: point.x * scale + view.pan.x,
      y: point.y * scale + view.pan.y,
    };
  }

  /** Keeps an overlay with a bounded size inside its measured viewport. */
  function clampOverlayCoordinate(
    coordinate: number,
    viewportSize: number,
    overlayMaximumSize: number,
  ): number {
    const margin = Math.min(BUNDLE_POPOVER_MARGIN, viewportSize / 2);
    const availableSize = Math.max(0, viewportSize - margin * 2);
    const overlaySize = Math.min(overlayMaximumSize, availableSize);
    const maximum = Math.max(margin, viewportSize - margin - overlaySize);
    return Math.min(Math.max(coordinate, margin), maximum);
  }

  /** Service list of an open bundle popover, anchored to the bundle line. */
  let bundlePopover = $derived.by(() => {
    const key = bundlePopoverKey;
    if (!key) return undefined;
    const entry = bundleViews.find((candidate) => candidate.key === key);
    if (!entry) return undefined;
    const anchor = worldToScreen({
      x: (entry.path.source.x + entry.path.target.x) / 2,
      y: (entry.path.source.y + entry.path.target.y) / 2,
    });
    return {
      key,
      title: entry.title,
      detailRows: entry.bundle.detailRows,
      position: {
        x: clampOverlayCoordinate(
          anchor.x + PIN_LABEL_INSET,
          viewport.width,
          BUNDLE_POPOVER_MAX_WIDTH,
        ),
        y: clampOverlayCoordinate(
          anchor.y + 10,
          viewport.height,
          BUNDLE_POPOVER_MAX_HEIGHT,
        ),
      },
    };
  });

  /** The selected host's local, view-only outgoing connection disclosure. */
  let dismissedHostConnectionId = $state<string>();
  let hostConnectionPanel = $derived.by(() => {
    const node = selectedNodeId ? nodeById.get(selectedNodeId) : undefined;
    if (node?.type !== "Host" || dismissedHostConnectionId === node.id)
      return undefined;
    return {
      hostId: node.id,
      hostLabel: node.data.name,
      detailRows: buildOutgoingConnectionDetails(scene, node.id),
    };
  });

  /** A changed selection reopens a host disclosure after Escape closed it. */
  $effect(() => {
    if (
      dismissedHostConnectionId !== undefined &&
      dismissedHostConnectionId !== selectedNodeId
    )
      dismissedHostConnectionId = undefined;
  });

  function toggleBundlePopover(bundle: BundleView): void {
    openedBundleKey = openedBundleKey === bundle.key ? undefined : bundle.key;
    const edgeId = bundle.bundle.policyEdgeIds[0];
    if (edgeId) onSelectEdge?.(edgeId);
  }

  /**
   * Authored `Runs` edges, keyed by relationship and endpoints.
   *
   * Ownership may only use an edge that projection membership confirms, so a
   * raw edge never adds membership. Segment containment draws no connector:
   * the projected host list and the enclosing frame already show it.
   */
  let structuralEdges = $derived(indexRunsEdges(graph.edges));

  let structuralLinks = $derived(
    buildStructuralLinks(sceneIndex, nodeRects, structuralEdges, {
      edgePresentation: (edge) => edgePresentation(edge.type),
      edgeAppearance,
    }),
  );

  /**
   * Ownership connectors to draw.
   *
   * Near detail shows every connector. Outside near detail only the lens
   * reveals a connector, and only between two entities the projection places.
   */
  let visibleStructuralLinks = $derived.by(() =>
    structuralLinks.filter(
      (link) =>
        showsStructuralEdges(detail) ||
        lens.structuralEdgeIds.has(link.edge.id),
    ),
  );

  /**
   * Anchor relationships of attached context the lens reveals.
   *
   * One line joins a revealed context card to the entity its projection anchor
   * names. The canvas reads the anchor record, never a raw edge.
   */
  let contextLinks = $derived(
    buildContextLinks(scene, {
      lensActive: lens.active,
      visibleIds: lens.visibleIds,
      entityRects,
      entityLabel,
    }),
  );

  let worldRects = $derived([...entityRects.values()]);

  function segmentName(segmentId: string): string {
    const node = nodeById.get(segmentId);
    return node?.type === "NetworkSegment" ? node.data.name : segmentId;
  }

  /** Name of a graph entity, for visible and accessible text. */
  function entityLabel(node: Node): string {
    return topologyEntityLabel(node);
  }

  function countLabel(count: number, singular: string, plural: string): string {
    return `${count} ${count === 1 ? singular : plural}`;
  }

  /** Directional flow rows in a bundle name, or text for a policy-only bundle. */
  function connectionSummary(bundle: TopologyConnectionBundle): string {
    return bundle.detailRows.length > 0
      ? bundle.detailRows.map(connectionDetailLabel).join(", ")
      : "no services";
  }

  function cueOf(entityId: string): "pending" | "placement-issue" | undefined {
    if (pendingIds.has(entityId)) return "pending";
    if (placementIssueIds.has(entityId)) return "placement-issue";
    return undefined;
  }

  function cueClasses(entityId: string): string[] {
    const cue = cueOf(entityId);
    return [
      cue === "pending" && "is-pending",
      cue === "placement-issue" && "is-placement-issue",
    ].filter((value): value is string => Boolean(value));
  }

  function setZoom(zoom: number) {
    view = { ...view, zoom: clampZoom(zoom) };
    detail = resolveDetailLevel(detail, view.zoom);
  }

  function panBy(x: number, y: number) {
    view = { ...view, pan: { x: view.pan.x + x, y: view.pan.y + y } };
  }

  function resetView() {
    view = { zoom: INITIAL_ZOOM, pan: { x: 0, y: 0 } };
    detail = initialDetailLevel(INITIAL_ZOOM);
  }

  function fitSceneToView() {
    const result = fitRects(worldRects, viewport);
    if (!result) return;
    view = { zoom: result.zoom, pan: result.pan };
    detail = initialDetailLevel(result.zoom);
  }

  function isGraphInteractive(target: EventTarget | null): boolean {
    return (
      target instanceof Element &&
      Boolean(target.closest("[data-graph-interactive]"))
    );
  }

  /**
   * True when the pointer target starts its own pointer gesture.
   *
   * A drag handle, a connection handle, or a pin owns the gesture. Every other
   * interactive entity keeps its click and focus behavior and still pans, so a
   * press on it is never a pointer dead zone.
   */
  function startsOwnGesture(target: EventTarget | null): boolean {
    return (
      target instanceof Element &&
      Boolean(target.closest("[data-graph-gesture]"))
    );
  }

  /**
   * Consumes a pan gesture that moved the viewport.
   *
   * The click that ends such a gesture must not also run an action.
   */
  function panConsumed(): boolean {
    if (!panMoved) return false;
    panMoved = false;
    return true;
  }

  function graphPosition(event: PointerEvent | MouseEvent): Point {
    const bounds = surfaceElement.getBoundingClientRect();
    return screenToWorld(
      { x: event.clientX - bounds.left, y: event.clientY - bounds.top },
      view,
    );
  }

  function handlePointerDown(event: PointerEvent) {
    if (event.button !== 0 || !event.isPrimary) return;
    // A drag click never outlives the gesture that produced it.
    clearClickSuppression();
    panMoved = false;
    // A drag or a connection starts its own gesture and keeps the pointer.
    if (startsOwnGesture(event.target)) return;

    // A press on an entity keeps its focus, so the lens follows the pointer.
    // Only blank space focuses the surface. Pointer capture stays off an
    // entity, so the click that selects it still reaches it.
    if (!isGraphInteractive(event.target)) {
      surfaceElement.focus();
      surfaceElement.setPointerCapture(event.pointerId);
    }
    panState = {
      pointerId: event.pointerId,
      start: { x: event.clientX, y: event.clientY },
      pan: { ...view.pan },
    };
  }

  function handlePointerMove(event: PointerEvent) {
    if (connectionState?.pointerId === event.pointerId) {
      pointerPosition = graphPosition(event);
      return;
    }
    if (dragState?.pointerId === event.pointerId) return moveDrag(event);
    if (panState?.pointerId !== event.pointerId) return;

    // A release outside the surface leaves no pointerup here, so a move that
    // reports no pressed button ends the pan instead of following the pointer.
    if ((event.buttons & 1) === 0) {
      releasePan(event);
      return;
    }

    const delta = pointerDelta(panState.start, {
      x: event.clientX,
      y: event.clientY,
    });
    if (exceedsDragThreshold(delta)) panMoved = true;

    view = {
      ...view,
      pan: {
        x: panState.pan.x + delta.x,
        y: panState.pan.y + delta.y,
      },
    };
  }

  function moveDrag(event: PointerEvent) {
    const state = dragState;
    if (!state) return;

    const delta = pointerDelta(state.start, {
      x: event.clientX,
      y: event.clientY,
    });
    if (!state.moved && !exceedsDragThreshold(delta)) return;
    state.moved = true;

    const positions = translatePositionMap(
      state.ids,
      state.origins,
      screenDeltaToWorld(delta, view.zoom),
    );
    scheduleGeometryUpdate(positions);
  }

  /**
   * Coalesces drag geometry into at most one update per animation frame.
   * The pending map always keeps the latest pointer sample.
   */
  function scheduleGeometryUpdate(positions: Map<string, Point>) {
    pendingGeometry = positions;
    if (geometryFrame !== undefined) return;
    geometryFrame = requestAnimationFrame(() => {
      geometryFrame = undefined;
      emitGeometryUpdate();
    });
  }

  function emitGeometryUpdate() {
    const positions = pendingGeometry;
    pendingGeometry = undefined;
    if (positions) onGeometryChange?.(positions);
  }

  /** Emits the last drag sample at once, so a pointer release loses nothing. */
  function flushGeometryUpdate() {
    if (geometryFrame !== undefined) {
      cancelAnimationFrame(geometryFrame);
      geometryFrame = undefined;
    }
    emitGeometryUpdate();
  }

  onDestroy(() => {
    if (geometryFrame !== undefined) cancelAnimationFrame(geometryFrame);
    geometryFrame = undefined;
    pendingGeometry = undefined;
  });

  /**
   * Starts a geometry-only drag. Positions come from the graph, so the drag
   * never authors membership, ownership, or a relationship.
   */
  function beginDrag(event: PointerEvent, ids: readonly string[]) {
    const element = event.currentTarget as SVGGElement;
    element.setPointerCapture(event.pointerId);
    clearClickSuppression();
    freezeContext();
    const origins = new Map<string, Point>();
    for (const id of ids) {
      const node = nodeById.get(id);
      if (node)
        origins.set(id, {
          x: node.view_data.x_pos,
          y: node.view_data.y_pos,
        });
    }
    dragState = {
      pointerId: event.pointerId,
      ids,
      origins,
      start: { x: event.clientX, y: event.clientY },
      moved: false,
      element,
    };
  }

  function startSegmentDrag(segmentId: string, event: PointerEvent) {
    if (!editable || event.button !== 0 || !event.isPrimary) return;
    event.stopPropagation();
    const segment = scene.segments.find((entry) => entry.id === segmentId);
    if (!segment) return;
    beginDrag(event, [
      segment.id,
      ...segment.hosts.map((host) => host.id),
      ...segment.hosts.flatMap((host) =>
        host.services.map((service) => service.id),
      ),
    ]);
  }

  function startEntityDrag(node: Node, event: PointerEvent) {
    if (!editable || event.button !== 0 || !event.isPrimary) return;
    if (isContextType(node.type)) return;
    event.stopPropagation();
    beginDrag(event, [node.id]);
  }

  function isContextType(type: Node["type"]): boolean {
    return (
      type === "Vulnerability" ||
      type === "Credential" ||
      type === "MissionCapability"
    );
  }

  function endDrag(event: PointerEvent) {
    const state = dragState;
    if (!state || state.pointerId !== event.pointerId) return;
    if (state.element.hasPointerCapture(event.pointerId))
      state.element.releasePointerCapture(event.pointerId);
    if (event.type === "pointerup" && state.moved) suppressClick = true;
    dragState = undefined;
    // The release commits the last pointer sample immediately.
    flushGeometryUpdate();
  }

  /**
   * Freezes the current attached-context positions for the drag session.
   *
   * Context keeps its world position while members move, and the layout skips
   * the ring search for frozen context. A new projection or fit clears this.
   */
  function freezeContext() {
    if (frozenContextPositions.size > 0) return;
    const frozen = new Map<string, Point>();
    for (const attachment of scene.attachments) {
      const position = layout.positions.get(attachment.id);
      if (position) frozen.set(attachment.id, { ...position });
    }
    if (frozen.size > 0)
      contextFreeze = { graphId: graphIdentity, projection, positions: frozen };
  }

  function releasePan(event: PointerEvent) {
    const state = panState;
    if (!state || state.pointerId !== event.pointerId) return;
    if (surfaceElement.hasPointerCapture(event.pointerId))
      surfaceElement.releasePointerCapture(event.pointerId);
    panState = undefined;
  }

  function handlePointerUp(event: PointerEvent) {
    if (connectionState?.pointerId === event.pointerId)
      return endConnection(event, event.type === "pointerup");
    if (dragState?.pointerId === event.pointerId) return endDrag(event);
    if (
      event.type === "pointerup" &&
      (!panState || panState.pointerId !== event.pointerId)
    )
      return;
    releasePan(event);
  }

  function startConnection(node: Node, event: PointerEvent) {
    if (
      !editable ||
      !onCreateConnection ||
      event.button !== 0 ||
      !event.isPrimary
    )
      return;

    event.stopPropagation();
    keyboardConnection = undefined;
    const element = event.currentTarget as SVGCircleElement;
    element.setPointerCapture(event.pointerId);
    connectionState = {
      pointerId: event.pointerId,
      sourceId: node.id,
      element,
    };
    pointerPosition = graphPosition(event);
  }

  function endConnection(event: PointerEvent, create: boolean) {
    const state = connectionState;
    if (!state || state.pointerId !== event.pointerId) return;

    const position = graphPosition(event);
    if (state.element.hasPointerCapture(event.pointerId))
      state.element.releasePointerCapture(event.pointerId);
    connectionState = undefined;
    pointerPosition = undefined;
    if (create)
      onCreateConnection?.(
        state.sourceId,
        nodeAtPosition(position)?.id,
        position,
      );
  }

  function nodeAtPosition(position: Point): Node | undefined {
    const candidates = [
      ...hostViews.flatMap((view) => [
        view.host.id,
        ...view.services.map((service) => service.scene.id),
      ]),
      ...scene.attachments.map((attachment) => attachment.id),
      ...scene.segments.map((segment) => segment.id),
    ];
    for (const id of candidates) {
      const rect = nodeRects.get(id);
      if (!rect || !pointInRect(position, rect)) continue;
      const node = nodeById.get(id);
      if (node) return node;
    }
    return undefined;
  }

  function handleWheel(event: WheelEvent) {
    event.preventDefault();
    setZoom(view.zoom + (event.deltaY < 0 ? ZOOM_STEP : -ZOOM_STEP));
  }

  function handleSurfaceClick(event: MouseEvent) {
    clearClickSuppression();
    if (panConsumed()) return;
    if (isGraphInteractive(event.target)) return;
    onClearSelection?.();
  }

  function handleContextMenu(event: MouseEvent) {
    if (isGraphInteractive(event.target)) return;
    contextPosition = graphPosition(event);
    onClearSelection?.();
  }

  function addNode(type: Node["type"]) {
    if (readOnly || !contextPosition) return;
    onAddNode?.(type, contextPosition);
  }

  /**
   * Consumes the click that a geometry drag produces.
   *
   * The flag is cleared by the next gesture, so a drag that ends away from its
   * own element cannot swallow a later selection.
   */
  function clearClickSuppression() {
    if (suppressClick) suppressClick = false;
  }

  function handleNodeClick(node: Node, event: MouseEvent) {
    event.stopPropagation();
    if (suppressClick) {
      suppressClick = false;
      return;
    }
    if (panConsumed()) return;
    activateNode(node);
  }

  /**
   * Selects an entity, or completes a pending keyboard connection.
   *
   * The keyboard path mirrors the pointer path: one activation names the
   * source, the next activation names the target.
   */
  function activateNode(node: Node): void {
    const pending = keyboardConnection;
    if (pending && pending.sourceId !== node.id) {
      const targetRect = nodeRects.get(node.id);
      if (targetRect) {
        onCreateConnection?.(pending.sourceId, node.id, rectCenter(targetRect));
        keyboardConnection = undefined;
        return;
      }
    }
    onSelectNode?.(node.id);
  }

  function startKeyboardConnection(node: Node, event: KeyboardEvent) {
    if (!editable || !onCreateConnection) return;
    event.preventDefault();
    event.stopPropagation();
    keyboardConnection = { sourceId: node.id };
  }

  function handlePinToggle(entityId: string, event: MouseEvent) {
    event.stopPropagation();
    if (panConsumed()) return;
    onTogglePin?.(entityId);
  }

  function handleKeydown(event: KeyboardEvent) {
    switch (event.key) {
      case "Escape":
        hoveredBundleKey = undefined;
        focusedBundleKey = undefined;
        openedBundleKey = undefined;
        if (selectedNodeId && nodeById.get(selectedNodeId)?.type === "Host")
          dismissedHostConnectionId = selectedNodeId;
        connectionState = undefined;
        keyboardConnection = undefined;
        pointerPosition = undefined;
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
        setZoom(view.zoom + ZOOM_STEP);
        break;
      case "-":
        event.preventDefault();
        setZoom(view.zoom - ZOOM_STEP);
        break;
      case "0":
        event.preventDefault();
        resetView();
        break;
      case "Delete":
      case "Backspace":
        if (!editable || !onDeleteSelection) break;
        event.preventDefault();
        onDeleteSelection();
        break;
    }
  }

  function handleNodeKeydown(node: Node, event: KeyboardEvent) {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    activateNode(node);
  }

  /**
   * DOM focus reveals the same lens as selection and clears when focus leaves.
   */
  function handleEntityFocus(entityId: string): void {
    keyboardFocusId = entityId;
  }

  function handleEntityBlur(entityId: string): void {
    if (keyboardFocusId === entityId) keyboardFocusId = undefined;
  }

  /** Entities the scene currently draws, for focus cleanup. */
  let drawnEntityIds = $derived(
    buildDrawnEntityIds(
      sceneIndex.projectedEntityIds,
      scene.attachments.map((attachment) => attachment.id),
      unplacedFloaters,
    ),
  );

  /**
   * Clears DOM focus state when its entity leaves the scene, so a deleted or
   * re-projected entity cannot keep a stale adjacency lens alive.
   */
  $effect(() => {
    const id = keyboardFocusId;
    if (id !== undefined && !drawnEntityIds.has(id))
      keyboardFocusId = undefined;
  });

  let stale = $derived(projectionStatus === "error");

  /**
   * Command tokens the canvas already ran.
   *
   * A delivery that repeats a token runs nothing. The counter is not reactive:
   * the effects that read it must not rerun when it changes.
   */
  let handledViewToken = 0;
  let handledAddToken = 0;
  /**
   * True when the gesture that is ending panned the viewport.
   *
   * A pan can start on an interactive entity, such as attached context or an
   * Unplaced card, so the trailing click of that gesture must not also select,
   * pin, or clear the selection.
   */
  let panMoved = false;

  /**
   * Fits a loaded graph once, as soon as the surface has a real viewport.
   * A hidden or collapsed surface (zero width or height) waits for its size.
   * The fit changes the view only. Graph geometry stays untouched.
   *
   * A graph the caller reports as not loaded never fits: the user still authors
   * it, so its content must not jump under the pointer. The identity is marked
   * as consumed, so a later load of a different graph fits normally.
   */
  $effect(() => {
    const identity = graphIdentity;
    if (!autoFit) {
      untrack(() => {
        if (autoFittedGraphId !== identity) autoFittedGraphId = identity;
      });
      return;
    }
    if (viewport.width <= 0 || viewport.height <= 0) return;
    if (autoFittedGraphId === identity) return;
    if (worldRects.length === 0) return;
    untrack(() => {
      autoFittedGraphId = identity;
      fitSceneToView();
    });
  });

  $effect(() => {
    const command = viewCommand;
    // Reading the token in the tracked scope reruns the effect on every change.
    if (!command || command.token === 0) return;
    if (command.token === handledViewToken) return;
    untrack(() => {
      handledViewToken = command.token;
      runViewCommand(command);
      onViewCommandHandled?.(command.token);
    });
  });

  $effect(() => {
    const request = addRequest;
    if (!request || request.token === 0) return;
    if (request.token === handledAddToken) return;
    untrack(() => {
      handledAddToken = request.token;
      // A request the canvas cannot run is still acknowledged, so it cannot
      // replay when the canvas later becomes editable.
      if (readOnly || !onAddNode) {
        onAddRequestHandled?.(request.token);
        return;
      }
      const anchor = contextPosition ?? {
        x: viewport.width / 2,
        y: viewport.height / 2,
      };
      onAddNode?.(request.type, screenToWorld(anchor, view));
      onAddRequestHandled?.(request.token);
    });
  });

  function runViewCommand(command: TopologyViewCommand): void {
    switch (command.kind) {
      case "fit":
        autoFittedGraphId = graphIdentity;
        releaseContextFreeze();
        fitSceneToView();
        break;
      case "reset":
        resetView();
        break;
      case "focus":
        if (command.entityId) focusEntity(command.entityId);
        break;
    }
  }

  /**
   * Centers one entity and zooms enough to make it legible.
   *
   * The command keeps a margin of surrounding topology visible and caps the
   * zoom. It changes the viewport only: world coordinates, segment footprints,
   * and attached-context placement stay untouched.
   */
  function focusEntity(entityId: string): void {
    const rect = entityRects.get(entityId);
    if (!rect) return;
    if (viewport.width <= 0 || viewport.height <= 0) return;

    const padded = {
      x: rect.x - FOCUS_MARGIN,
      y: rect.y - FOCUS_MARGIN,
      width: rect.width + 2 * FOCUS_MARGIN,
      height: rect.height + 2 * FOCUS_MARGIN,
    };
    const fitted = fitRects([padded], viewport, 0)?.zoom ?? view.zoom;
    const zoom = clampZoom(Math.min(fitted, FOCUS_MAX_ZOOM));
    const center = rectCenter(rect);
    const scale = zoom / 100;
    view = {
      zoom,
      pan: {
        x: viewport.width / 2 - center.x * scale,
        y: viewport.height / 2 - center.y * scale,
      },
    };
    detail = initialDetailLevel(zoom);
  }

  function releaseContextFreeze() {
    if (contextFreeze) contextFreeze = undefined;
  }
</script>

<section class="topology-shell" aria-label={ariaLabel}>
  <!--
    Connection and pin controls render next to the entity they belong to.
    Each control is a sibling of the entity, never nested inside its button.
  -->
  {#snippet connectionHandle(handle: TopologyConnectionHandleView)}
    <circle
      class="topology-connection-handle"
      class:is-source={connectionSourceId === handle.node.id}
      cx={handle.position.x + (handle.side === "right" ? handle.width : 0)}
      cy={handle.position.y + handle.offset}
      r="6"
      role="button"
      tabindex="0"
      data-graph-interactive
      data-graph-gesture
      aria-label={`Create connection from ${handle.node.type} ${handle.node.data.name}`}
      onpointerdown={(event) => startConnection(handle.node, event)}
      onkeydown={(event) => startKeyboardConnection(handle.node, event)}
    />
  {/snippet}
  {#snippet pinControl(target: PinTarget)}
    <g
      class="topology-pin"
      class:is-pinned={target.pinned}
      transform={`translate(${target.position.x} ${target.position.y})`}
      data-pin-entity={target.id}
      role="button"
      tabindex="0"
      aria-pressed={target.pinned}
      aria-label={`${target.pinned ? "Unpin" : "Pin"} ${target.label}`}
      data-graph-interactive
      onclick={(event) => handlePinToggle(target.id, event)}
      onkeydown={(event) => {
        if (event.key !== "Enter" && event.key !== " ") return;
        event.preventDefault();
        event.stopPropagation();
        onTogglePin?.(target.id);
      }}
    >
      <rect width={PIN_SIZE} height={PIN_SIZE} rx="4" />
      <path
        d="M8 1.5a3.4 3.4 0 0 1 3.4 3.4c0 1.5-.9 2.4-1.7 3.4l-.5 3.2h-2.4l-.5-3.2C5.5 7.3 4.6 6.4 4.6 4.9A3.4 3.4 0 0 1 8 1.5Z"
      />
    </g>
  {/snippet}
  <ContextMenu.Root>
    <ContextMenu.Trigger
      class="topology-context-trigger"
      oncontextmenu={handleContextMenu}
    >
      <!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
      <div
        class="topology-surface"
        bind:this={surfaceElement}
        role="application"
        tabindex="0"
        data-stale={stale ? "true" : undefined}
        aria-label={`${ariaLabel}. Drag blank space to pan${editable ? " or drag a segment header or card to reposition it" : ""}. Use the mouse wheel or keyboard to zoom.`}
        style:--grid-offset-x={`${view.pan.x}px`}
        style:--grid-offset-y={`${view.pan.y}px`}
        style:--minor-grid-size={`${gridSize}px`}
        style:--major-grid-size={`${gridSize * 5}px`}
        bind:clientWidth={viewport.width}
        bind:clientHeight={viewport.height}
        onpointerdown={handlePointerDown}
        onpointermove={handlePointerMove}
        onpointerup={handlePointerUp}
        onpointercancel={handlePointerUp}
        onwheel={handleWheel}
        onclick={handleSurfaceClick}
        onkeydown={handleKeydown}
      >
        <svg
          class="topology-graph"
          viewBox={`0 0 ${viewport.width} ${viewport.height}`}
          aria-label="Topology graph"
        >
          <defs>
            <marker
              id={arrowMarkerId}
              markerWidth="8"
              markerHeight="8"
              refX="7"
              refY="3"
              orient="auto"
              ><path class="topology-arrow" d="M0 0 8 3 0 6Z" /></marker
            >
          </defs>
          <g
            class="topology-world"
            class:is-stale={stale}
            transform={worldTransform}
          >
            <!-- Visual bundle lines remain behind segment frames. -->
            {#each bundleViews as bundle (bundle.key)}
              {@const path = `M ${bundle.path.source.x} ${bundle.path.source.y} L ${bundle.path.target.x} ${bundle.path.target.y}`}
              <g
                class={[
                  "topology-bundle-visual",
                  bundle.selected && "is-selected",
                  bundle.dimmed && "is-dimmed",
                ]}
                data-bundle-visual={bundle.key}
                style:--bundle-opacity={bundle.appearance?.opacity}
                style:--bundle-stroke={bundle.appearance?.stroke}
                style:--bundle-stroke-width={bundle.appearance?.strokeWidth}
              >
                <path
                  class="topology-bundle-line"
                  d={path}
                  marker-end={`url(#${arrowMarkerId})`}
                />
                <text
                  class="topology-bundle-count"
                  x={(bundle.path.source.x + bundle.path.target.x) / 2}
                  y={(bundle.path.source.y + bundle.path.target.y) / 2 - 8}
                  text-anchor="middle">{bundle.count}</text
                >
              </g>
            {/each}
            {#each scene.segments as segment (segment.id)}
              {@const frame = layout.frames.get(segment.id)}
              {#if frame}
                <g
                  class={[
                    "topology-segment",
                    selectedNodeId === segment.id && "is-selected",
                    isPinned(segment.id) && "is-pinned",
                    isDimmed(segment.id) && "is-dimmed",
                    ...cueClasses(segment.id),
                  ]}
                  transform={`translate(${frame.position.x} ${frame.position.y})`}
                  data-segment-id={segment.id}
                  data-projection-cue={cueOf(segment.id)}
                  role="group"
                  aria-label={`${segment.node.data.name} segment, ${countLabel(
                    segment.segment.host_count,
                    "host",
                    "hosts",
                  )}, ${countLabel(
                    segment.segment.service_count,
                    "service",
                    "services",
                  )}${detail === "far" ? `, ${countLabel(segment.segment.context_count, "context item", "context items")}` : ""}`}
                >
                  <rect
                    class="topology-segment-frame"
                    width={frame.size.width}
                    height={frame.size.height}
                    rx="18"
                  />
                </g>
              {/if}
            {/each}
            <!--
              Hit areas sit above segment frames but below headers and members.
              This leaves the single visual line readable behind frames while its
              exposed portions retain pointer ownership.
            -->
            {#each bundleViews as bundle (bundle.key)}
              {@const path = `M ${bundle.path.source.x} ${bundle.path.source.y} L ${bundle.path.target.x} ${bundle.path.target.y}`}
              <g
                class="topology-bundle"
                data-bundle-key={bundle.key}
                data-bundle-from={bundle.bundle.fromSegmentId}
                data-bundle-to={bundle.bundle.toSegmentId}
                data-bundle-connections={bundle.bundle.connectionCount}
                role="button"
                tabindex="0"
                aria-expanded={bundlePopoverKey === bundle.key}
                aria-label={bundle.label}
                data-graph-interactive
                style:--bundle-opacity={bundle.appearance?.opacity}
                style:--bundle-stroke={bundle.appearance?.stroke}
                style:--bundle-stroke-width={bundle.appearance?.strokeWidth}
                onpointerenter={() => (hoveredBundleKey = bundle.key)}
                onpointerleave={() => {
                  if (hoveredBundleKey === bundle.key)
                    hoveredBundleKey = undefined;
                }}
                onfocus={() => (focusedBundleKey = bundle.key)}
                onblur={() => {
                  if (focusedBundleKey === bundle.key)
                    focusedBundleKey = undefined;
                }}
                onclick={(event) => {
                  event.stopPropagation();
                  if (panConsumed()) return;
                  toggleBundlePopover(bundle);
                }}
                onkeydown={(event) => {
                  if (event.key !== "Enter" && event.key !== " ") return;
                  event.preventDefault();
                  toggleBundlePopover(bundle);
                }}
              >
                <path class="topology-bundle-hit" d={path} />
              </g>
            {/each}
            {#each scene.segments as segment (segment.id)}
              {@const frame = layout.frames.get(segment.id)}
              {#if frame}
                <!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
                <g
                  class={[
                    "topology-segment-header",
                    isDimmed(segment.id) && "is-dimmed",
                  ]}
                  transform={`translate(${frame.position.x} ${frame.position.y})`}
                  data-segment-header={segment.id}
                  data-graph-interactive={editable || onSelectNode
                    ? true
                    : undefined}
                  data-graph-gesture={editable ? true : undefined}
                  onpointerdown={editable
                    ? (event) => startSegmentDrag(segment.id, event)
                    : undefined}
                  onclick={onSelectNode
                    ? (event) => handleNodeClick(segment.node, event)
                    : undefined}
                  onkeydown={onSelectNode
                    ? (event) => handleNodeKeydown(segment.node, event)
                    : undefined}
                  onfocus={onSelectNode
                    ? () => handleEntityFocus(segment.id)
                    : undefined}
                  onblur={onSelectNode
                    ? () => handleEntityBlur(segment.id)
                    : undefined}
                  tabindex={onSelectNode ? 0 : undefined}
                  role={onSelectNode ? "button" : undefined}
                >
                  <rect
                    class="topology-segment-header-bg"
                    width={frame.size.width}
                    height={SEGMENT_HEADER_HEIGHT}
                    rx="18"
                  />
                  <text class="topology-segment-name" x="16" y="19"
                    >{segment.node.data.name}</text
                  >
                  <text class="topology-segment-meta" x="16" y="33"
                    >{countLabel(segment.segment.host_count, "host", "hosts")} ·
                    {countLabel(
                      segment.segment.service_count,
                      "service",
                      "services",
                    )}{detail === "far"
                      ? ` · ${countLabel(segment.segment.context_count, "context item", "context items")}`
                      : ""}</text
                  >
                  {#if segment.node.data.cidr && frame.size.width >= CIDR_MIN_WIDTH}
                    <text
                      class="topology-segment-cidr"
                      x={frame.size.width - labelInset(segment.id, 16)}
                      y="19"
                      text-anchor="end">{segment.node.data.cidr}</text
                    >
                  {/if}
                  {#if selfPolicyIds.has(segment.id)}
                    <g
                      class="topology-self-policy"
                      role="img"
                      aria-label={`${segment.node.data.name} self-segment policy`}
                    >
                      <rect
                        x={frame.size.width - 104}
                        y="24"
                        width="88"
                        height="16"
                        rx="8"
                      />
                      <text
                        x={frame.size.width - 60}
                        y="37"
                        text-anchor="middle">self-policy</text
                      >
                    </g>
                  {/if}
                </g>
                {#if pinTargetById.get(segment.id)}
                  {@render pinControl(pinTargetById.get(segment.id)!)}
                {/if}
              {/if}
            {/each}
            {#each visibleStructuralLinks as link (link.edge.id)}
              {@const path = connectRects(link.sourceRect, link.targetRect)}
              <g
                class={[
                  "topology-structural-edge",
                  selectedEdgeId === link.edge.id && "is-selected",
                  isDimmed(link.edge.from_id) && "is-dimmed",
                ]}
                data-edge-id={link.edge.id}
                style:--structural-color={link.color}
                style:--structural-dash={link.dash ?? "none"}
                style:--structural-opacity={link.appearance?.opacity}
                style:--structural-stroke={link.appearance?.stroke}
                style:--structural-stroke-width={link.appearance?.strokeWidth}
                role={onSelectEdge ? "button" : "img"}
                aria-label={`${link.label} relationship`}
                data-graph-interactive={onSelectEdge ? true : undefined}
                tabindex={onSelectEdge ? 0 : undefined}
                onclick={onSelectEdge
                  ? (event) => {
                      event.stopPropagation();
                      if (panConsumed()) return;
                      onSelectEdge?.(link.edge.id);
                    }
                  : undefined}
                onkeydown={onSelectEdge
                  ? (event) => {
                      if (event.key !== "Enter" && event.key !== " ") return;
                      event.preventDefault();
                      onSelectEdge?.(link.edge.id);
                    }
                  : undefined}
              >
                <path
                  class="topology-structural-path"
                  d={`M ${path.source.x} ${path.source.y} L ${path.target.x} ${path.target.y}`}
                />
                <text
                  class="topology-structural-label"
                  x={(path.source.x + path.target.x) / 2}
                  y={(path.source.y + path.target.y) / 2}>{link.label}</text
                >
              </g>
            {/each}
            {#each contextLinks as link (link.key)}
              <g
                class="topology-anchor-link"
                role="img"
                aria-label={link.label}
              >
                <path
                  d={`M ${link.path.source.x} ${link.path.source.y} L ${
                    link.path.target.x
                  } ${link.path.target.y}`}
                />
              </g>
            {/each}
            {#each hostViews as view (view.host.id)}
              {#if revealsHost(view.host.id)}
                {#if detail === "near"}
                  <g
                    class={[
                      "topology-host-card",
                      isPinned(view.host.id) && "is-pinned",
                      isDimmed(view.host.id) && "is-dimmed",
                      ...cueClasses(view.host.id),
                    ]}
                    data-node-id={view.host.id}
                    data-projection-cue={cueOf(view.host.id)}
                    data-graph-gesture={editable ? true : undefined}
                    onfocusin={() => handleEntityFocus(view.host.id)}
                    onfocusout={() => handleEntityBlur(view.host.id)}
                  >
                    <CanvasNode
                      node={view.host.node}
                      position={view.position}
                      selected={selectedNodeId === view.host.id}
                      source={connectionSourceId === view.host.id}
                      dragging={false}
                      appearance={nodeAppearance?.(view.host.node)}
                      onclick={onSelectNode
                        ? (event) => handleNodeClick(view.host.node, event)
                        : undefined}
                      onpointerdown={editable
                        ? (event) => startEntityDrag(view.host.node, event)
                        : undefined}
                    />
                  </g>
                {:else}
                  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
                  <g
                    class={[
                      "topology-host-glyph",
                      selectedNodeId === view.host.id && "is-selected",
                      isPinned(view.host.id) && "is-pinned",
                      isDimmed(view.host.id) && "is-dimmed",
                      ...cueClasses(view.host.id),
                    ]}
                    transform={`translate(${view.position.x} ${view.position.y})`}
                    data-node-id={view.host.id}
                    data-projection-cue={cueOf(view.host.id)}
                    style:--node-card-fill={nodeAppearance?.(view.host.node)
                      ?.cardFill}
                    style:--node-card-opacity={nodeAppearance?.(view.host.node)
                      ?.cardOpacity}
                    style:--node-card-stroke={nodeAppearance?.(view.host.node)
                      ?.cardStroke}
                    style:--node-card-stroke-width={nodeAppearance?.(
                      view.host.node,
                    )?.cardStrokeWidth}
                    data-graph-interactive={editable || onSelectNode
                      ? true
                      : undefined}
                    data-graph-gesture={editable ? true : undefined}
                    role={onSelectNode ? "button" : undefined}
                    tabindex={onSelectNode ? 0 : undefined}
                    aria-label={`Host ${view.host.node.data.name}, ${countLabel(
                      view.host.host.service_count,
                      "service",
                      "services",
                    )}`}
                    onclick={onSelectNode
                      ? (event) => handleNodeClick(view.host.node, event)
                      : undefined}
                    onkeydown={onSelectNode
                      ? (event) => handleNodeKeydown(view.host.node, event)
                      : undefined}
                    onfocus={onSelectNode
                      ? () => handleEntityFocus(view.host.id)
                      : undefined}
                    onblur={onSelectNode
                      ? () => handleEntityBlur(view.host.id)
                      : undefined}
                    onpointerdown={editable
                      ? (event) => startEntityDrag(view.host.node, event)
                      : undefined}
                  >
                    <rect
                      class="topology-host-glyph-card"
                      width={NODE_WIDTH}
                      height={HOST_GLYPH_HEIGHT}
                      rx="6"
                    />
                    <text class="topology-host-glyph-name" x="10" y="20"
                      >{view.host.node.data.name}</text
                    >
                    <text
                      class="topology-host-glyph-count"
                      x={NODE_WIDTH - labelInset(view.host.id, 10)}
                      y="20"
                      text-anchor="end"
                      >{countLabel(
                        view.host.host.service_count,
                        "service",
                        "services",
                      )}</text
                    >
                  </g>
                {/if}
                {#if connectionHandleById.get(view.host.id)}
                  {@render connectionHandle(
                    connectionHandleById.get(view.host.id)!,
                  )}
                {/if}
                {#if pinTargetById.get(view.host.id)}
                  {@render pinControl(pinTargetById.get(view.host.id)!)}
                {/if}
                {#each view.services as service (service.scene.id)}
                  {#if revealsService(service.scene.id)}
                    <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
                    <g
                      class={[
                        "topology-service",
                        selectedNodeId === service.scene.id && "is-selected",
                        isPinned(service.scene.id) && "is-pinned",
                        isDimmed(service.scene.id) && "is-dimmed",
                        ...cueClasses(service.scene.id),
                      ]}
                      transform={`translate(${service.position.x} ${service.position.y})`}
                      data-node-id={service.scene.id}
                      data-projection-cue={cueOf(service.scene.id)}
                      style:--node-card-fill={nodeAppearance?.(
                        service.scene.node,
                      )?.cardFill}
                      style:--node-card-opacity={nodeAppearance?.(
                        service.scene.node,
                      )?.cardOpacity}
                      style:--node-card-stroke={nodeAppearance?.(
                        service.scene.node,
                      )?.cardStroke}
                      style:--node-card-stroke-width={nodeAppearance?.(
                        service.scene.node,
                      )?.cardStrokeWidth}
                      data-graph-interactive={editable || onSelectNode
                        ? true
                        : undefined}
                      data-graph-gesture={editable ? true : undefined}
                      role={onSelectNode ? "button" : undefined}
                      tabindex={onSelectNode ? 0 : undefined}
                      aria-label={`Service ${service.scene.node.data.name}`}
                      onclick={onSelectNode
                        ? (event) => handleNodeClick(service.scene.node, event)
                        : undefined}
                      onkeydown={onSelectNode
                        ? (event) =>
                            handleNodeKeydown(service.scene.node, event)
                        : undefined}
                      onfocus={onSelectNode
                        ? () => handleEntityFocus(service.scene.id)
                        : undefined}
                      onblur={onSelectNode
                        ? () => handleEntityBlur(service.scene.id)
                        : undefined}
                      onpointerdown={editable
                        ? (event) => startEntityDrag(service.scene.node, event)
                        : undefined}
                    >
                      <rect
                        class="topology-service-card"
                        width={SERVICE_SIZE.width}
                        height={SERVICE_SIZE.height}
                        rx="6"
                      />
                      <text class="topology-service-name" x="10" y="21"
                        >{service.scene.node.data.name}</text
                      >
                      <text
                        class="topology-service-port"
                        x={SERVICE_SIZE.width -
                          labelInset(service.scene.id, 10)}
                        y="21"
                        text-anchor="end"
                        >{service.scene.node.data.port}/{service.scene.node.data
                          .protocol}</text
                      >
                    </g>
                    {#if connectionHandleById.get(service.scene.id)}
                      {@render connectionHandle(
                        connectionHandleById.get(service.scene.id)!,
                      )}
                    {/if}
                    {#if pinTargetById.get(service.scene.id)}
                      {@render pinControl(pinTargetById.get(service.scene.id)!)}
                    {/if}
                  {/if}
                {/each}
              {/if}
            {/each}
            {#each scene.attachments as attachment (attachment.id)}
              {@const position = layout.positions.get(attachment.id)}
              {@const presentation = nodePresentation(attachment.node.type)}
              {#if position && presentation && revealsContext(attachment.id)}
                {@const Glyph = presentation.glyph}
                <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
                <g
                  class={[
                    "topology-context",
                    selectedNodeId === attachment.id && "is-selected",
                    isPinned(attachment.id) && "is-pinned",
                    isDimmed(attachment.id) && "is-dimmed",
                    ...cueClasses(attachment.id),
                  ]}
                  transform={`translate(${position.x} ${position.y})`}
                  data-node-id={attachment.id}
                  data-projection-cue={cueOf(attachment.id)}
                  data-graph-interactive={onSelectNode ? true : undefined}
                  role={onSelectNode ? "button" : undefined}
                  tabindex={onSelectNode ? 0 : undefined}
                  aria-label={`${attachment.node.type} ${entityLabel(
                    attachment.node,
                  )}`}
                  style:--node-color={presentation.color}
                  onclick={onSelectNode
                    ? (event) => handleNodeClick(attachment.node, event)
                    : undefined}
                  onkeydown={onSelectNode
                    ? (event) => handleNodeKeydown(attachment.node, event)
                    : undefined}
                  onfocus={onSelectNode
                    ? () => handleEntityFocus(attachment.id)
                    : undefined}
                  onblur={onSelectNode
                    ? () => handleEntityBlur(attachment.id)
                    : undefined}
                >
                  <rect
                    class="topology-context-card"
                    width={CONTEXT_SIZE.width}
                    height={CONTEXT_SIZE.height}
                    rx="10"
                  />
                  <Glyph />
                  <text class="topology-context-title" x="30" y="30"
                    >{entityLabel(attachment.node)}</text
                  >
                  <text class="topology-context-sub" x="30" y="48"
                    >{attachment.node.type}</text
                  >
                </g>
                {#if pinTargetById.get(attachment.id)}
                  {@render pinControl(pinTargetById.get(attachment.id)!)}
                {/if}
              {/if}
            {/each}
            {#each unplacedFloaters as floater (floater.entry.key)}
              <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
              <g
                class={[
                  "topology-unplaced",
                  `is-${floater.entry.status.replace("_", "-")}`,
                  isDimmed(floater.node.id) && "is-dimmed",
                ]}
                transform={`translate(${floater.position.x} ${floater.position.y})`}
                data-node-id={floater.node.id}
                data-unplaced-status={floater.entry.status}
                data-unplaced-reason={unplacedReasonCode(floater.entry)}
                data-projection-cue={floater.entry.status === "pending"
                  ? "pending"
                  : "placement-issue"}
                data-graph-interactive={onSelectNode ? true : undefined}
                role={onSelectNode ? "button" : undefined}
                tabindex={onSelectNode ? 0 : undefined}
                aria-label={`${floater.node.type} ${entityLabel(
                  floater.node,
                )}, ${unplacedReason(floater.entry)}`}
                onclick={onSelectNode
                  ? (event) => handleNodeClick(floater.node, event)
                  : undefined}
                onkeydown={onSelectNode
                  ? (event) => handleNodeKeydown(floater.node, event)
                  : undefined}
                onfocus={onSelectNode
                  ? () => handleEntityFocus(floater.node.id)
                  : undefined}
                onblur={onSelectNode
                  ? () => handleEntityBlur(floater.node.id)
                  : undefined}
              >
                <title
                  >{`${floater.node.type} ${entityLabel(floater.node)} · ${unplacedReason(
                    floater.entry,
                  )}`}</title
                >
                <rect
                  class="topology-unplaced-card"
                  width={NODE_WIDTH}
                  height={UNPLACED_CARD_HEIGHT}
                  rx="6"
                />
                <text class="topology-unplaced-mark" x="8" y="19">!</text>
                <text class="topology-unplaced-name" x="22" y="19"
                  >{entityLabel(floater.node)}</text
                >
                <text class="topology-unplaced-reason" x="22" y="36"
                  >{unplacedReason(floater.entry)}</text
                >
              </g>
              {#if pinTargetById.get(floater.node.id)}
                {@render pinControl(pinTargetById.get(floater.node.id)!)}
              {/if}
            {/each}
            {#if connectionState && pointerPosition}
              {@const sourceRect = nodeRects.get(connectionState.sourceId)}
              {#if sourceRect}
                {@const center = rectCenter(sourceRect)}
                <path
                  class="topology-connection-preview"
                  d={`M ${center.x} ${center.y} L ${pointerPosition.x} ${pointerPosition.y}`}
                  marker-end={`url(#${arrowMarkerId})`}
                />
              {/if}
            {/if}
          </g>
        </svg>
        {#if bundlePopover}
          <div
            class="topology-bundle-popover"
            role="tooltip"
            data-bundle-popover={bundlePopover.key}
            style:left={`${bundlePopover.position.x}px`}
            style:top={`${bundlePopover.position.y}px`}
          >
            <p class="topology-bundle-popover-title">{bundlePopover.title}</p>
            {#if bundlePopover.detailRows.length > 0}
              <ul class="topology-bundle-popover-services">
                {#each bundlePopover.detailRows as row (`${row.serviceId}:${row.sourceHostId}:${row.targetHostId}`)}
                  <li>{connectionDetailLabel(row)}</li>
                {/each}
              </ul>
            {:else}
              <p class="topology-bundle-popover-empty">No services</p>
            {/if}
          </div>
        {/if}
        {#if hostConnectionPanel}
          <aside
            class="topology-host-connections"
            data-host-connections={hostConnectionPanel.hostId}
            aria-label={`${hostConnectionPanel.hostLabel} outgoing connections`}
          >
            <p class="topology-host-connections-title">
              {hostConnectionPanel.hostLabel} outgoing connections
            </p>
            {#if hostConnectionPanel.detailRows.length > 0}
              <ul class="topology-host-connections-list">
                {#each hostConnectionPanel.detailRows as row (`${row.serviceId}:${row.sourceHostId}:${row.targetHostId}`)}
                  <li>{connectionDetailLabel(row)}</li>
                {/each}
              </ul>
            {:else}
              <p class="topology-host-connections-empty">
                No outgoing connections
              </p>
            {/if}
          </aside>
        {/if}
      </div>
    </ContextMenu.Trigger>
    <ContextMenu.Portal>
      <ContextMenu.Content
        class="dashboard-menu-content"
        sideOffset={6}
        aria-label="Canvas actions"
      >
        {#if !readOnly && onAddNode}
          <ContextMenu.Sub>
            <ContextMenu.SubTrigger class="dashboard-menu-item"
              >Add</ContextMenu.SubTrigger
            >
            <ContextMenu.Portal>
              <ContextMenu.SubContent
                class="dashboard-menu-content"
                sideOffset={6}
              >
                {#each TOPOLOGY_NODE_TYPES as type (type)}
                  <ContextMenu.Item
                    class="dashboard-menu-item"
                    onSelect={() => addNode(type)}>{type}</ContextMenu.Item
                  >
                {/each}
              </ContextMenu.SubContent>
            </ContextMenu.Portal>
          </ContextMenu.Sub>
          <ContextMenu.Separator class="dashboard-menu-separator" />
        {/if}
        {#if editable && onDeleteSelection}
          <ContextMenu.Item
            class="dashboard-menu-item"
            onSelect={() => onDeleteSelection?.()}
            >Delete selection</ContextMenu.Item
          >
          <ContextMenu.Separator class="dashboard-menu-separator" />
        {/if}
        {#if onClearPins && pinnedEntityIds.length > 0}
          <ContextMenu.Item
            class="dashboard-menu-item"
            onSelect={() => onClearPins?.()}
            >Clear pins ({pinnedEntityIds.length})</ContextMenu.Item
          >
          <ContextMenu.Separator class="dashboard-menu-separator" />
        {/if}
        {#if onCompareGraphs}
          <ContextMenu.Item
            class="dashboard-menu-item"
            onSelect={onCompareGraphs}
            >Compare with another graph</ContextMenu.Item
          >
        {/if}
      </ContextMenu.Content>
    </ContextMenu.Portal>
  </ContextMenu.Root>
  <div class="topology-status" aria-live="polite">
    {#if projectionStatus === "pending"}
      <p class="topology-status-item is-pending" data-status="pending">
        Updating topology
      </p>
    {/if}
    {#if stale}
      <p class="topology-status-item is-stale" data-status="error" role="alert">
        Topology grouping is unavailable. Graph editing remains available.
      </p>
    {/if}
    {#if projectionSource === "draft" && scene.flowGroups.length > 0}
      <p class="topology-status-item is-draft" data-status="draft-reachability">
        Draft reachability · Save before simulation
      </p>
    {/if}
    {#if keyboardConnection}
      <p
        class="topology-status-item is-connection"
        data-status="connection-source"
      >
        Connecting from {connectionSourceLabel}. Activate a target entity, or
        press Escape to cancel.
      </p>
    {/if}
    {#if placementIssueIds.size > 0}
      <p
        class="topology-status-item is-placement"
        data-status="placement-issues"
      >
        {countLabel(
          placementIssueIds.size,
          "placement issue",
          "placement issues",
        )}
      </p>
    {/if}
  </div>
  <div class="topology-controls" aria-label="Canvas zoom controls">
    <button
      type="button"
      aria-label="Zoom out"
      onclick={() => setZoom(view.zoom - ZOOM_STEP)}>&minus;</button
    ><output aria-label="Zoom level" aria-live="polite" aria-atomic="true"
      >{view.zoom}%</output
    ><button
      type="button"
      aria-label="Zoom in"
      onclick={() => setZoom(view.zoom + ZOOM_STEP)}>+</button
    >
  </div>
</section>

<style>
  .topology-shell {
    --topology-dim-opacity: 0.25;
    position: relative;
    height: 100%;
    min-height: 0;
    overflow: hidden;
    background: var(--ui-color-canvas);
  }
  :global(.topology-context-trigger) {
    display: block;
    height: 100%;
  }
  .topology-surface {
    position: relative;
    width: 100%;
    height: 100%;
    touch-action: none;
    cursor: grab;
    outline: 0;
    background-color: var(--ui-color-canvas);
    background-image:
      linear-gradient(
        color-mix(in srgb, var(--ui-color-border) 33%, transparent) 1px,
        transparent 1px
      ),
      linear-gradient(
        90deg,
        color-mix(in srgb, var(--ui-color-border) 33%, transparent) 1px,
        transparent 1px
      );
    background-position:
      var(--grid-offset-x) var(--grid-offset-y),
      var(--grid-offset-x) var(--grid-offset-y);
    background-size:
      var(--minor-grid-size) var(--minor-grid-size),
      var(--major-grid-size) var(--major-grid-size);
    transition: background-size 120ms ease-out;
  }
  .topology-surface:active {
    cursor: grabbing;
  }
  .topology-surface:focus-visible {
    outline: 2px solid var(--ui-color-focus);
    outline-offset: -2px;
  }
  .topology-surface:has([data-graph-interactive]) {
    cursor: grab;
  }
  .topology-graph {
    display: block;
    width: 100%;
    height: 100%;
    overflow: visible;
  }
  .topology-world.is-stale {
    opacity: 0.65;
    filter: saturate(0.4);
  }
  .topology-arrow {
    fill: var(
      --topology-arrow-color,
      var(--ui-color-edge-segment-reachability)
    );
  }
  .topology-bundle {
    cursor: pointer;
  }
  .topology-bundle-hit {
    fill: none;
    stroke: transparent;
    stroke-width: 16;
    /* Keep the transparent stroke eligible for pointer hit testing. */
    pointer-events: stroke;
  }
  .topology-bundle-line {
    fill: none;
    pointer-events: none;
    stroke: var(--bundle-stroke, var(--ui-color-edge-segment-reachability));
    stroke-opacity: var(--bundle-opacity, 1);
    stroke-width: var(--bundle-stroke-width, 3);
  }
  .topology-bundle-visual.is-selected .topology-bundle-line {
    stroke: var(--ui-color-focus);
    stroke-width: 4;
  }
  .topology-bundle:focus-visible .topology-bundle-hit {
    stroke: var(--ui-color-focus);
    stroke-opacity: 0.35;
  }
  .topology-bundle:focus,
  .topology-bundle:focus-visible {
    outline: none;
  }
  .topology-bundle-count {
    fill: var(--ui-color-text);
    font: var(--ui-text-xs) var(--ui-font-mono);
    font-weight: 700;
    pointer-events: none;
  }
  .topology-bundle-popover {
    position: absolute;
    z-index: 2;
    box-sizing: border-box;
    width: min(16rem, calc(100% - 1rem));
    min-width: 0;
    max-width: calc(100% - 1rem);
    max-height: min(12rem, calc(100% - 1rem));
    overflow-wrap: anywhere;
    overflow-y: auto;
    padding: var(--ui-space-2);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
    color: var(--ui-color-text);
    font-size: var(--ui-text-sm);
    /* The popover only describes the bundle, so it never holds the pointer. */
    pointer-events: none;
  }
  .topology-bundle-popover-title {
    margin: 0 0 var(--ui-space-1);
    font-weight: 700;
  }
  .topology-bundle-popover-services {
    margin: 0;
    padding-left: var(--ui-space-4);
  }
  .topology-bundle-popover-empty {
    margin: 0;
    color: var(--ui-color-text-muted);
  }
  .topology-host-connections {
    position: absolute;
    z-index: 2;
    top: var(--ui-space-3);
    right: var(--ui-space-3);
    min-width: 14rem;
    max-width: 22rem;
    padding: var(--ui-space-2);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
    color: var(--ui-color-text);
    font-size: var(--ui-text-sm);
  }
  .topology-host-connections-title {
    margin: 0 0 var(--ui-space-1);
    font-weight: 700;
  }
  .topology-host-connections-list {
    display: grid;
    gap: var(--ui-space-1);
    margin: 0;
    padding-left: var(--ui-space-4);
  }
  .topology-host-connections-empty {
    margin: 0;
    color: var(--ui-color-text-muted);
  }
  .topology-segment-frame {
    fill: var(--ui-color-paper);
    fill-opacity: 0.55;
    stroke: var(--ui-color-border);
    stroke-width: 1.5;
  }
  .topology-segment.is-selected .topology-segment-frame {
    stroke: var(--ui-color-focus);
    stroke-width: 3;
  }
  .topology-segment.is-pending .topology-segment-frame {
    stroke: var(--ui-color-warning);
    stroke-dasharray: 6 4;
  }
  .topology-segment.is-placement-issue .topology-segment-frame {
    stroke: var(--ui-color-danger);
    stroke-dasharray: 2 3;
  }
  .topology-segment-header {
    cursor: default;
  }
  .topology-segment-header[data-graph-interactive] {
    cursor: move;
  }
  .topology-segment-header:focus-visible {
    outline: none;
  }
  .topology-segment-header-bg {
    fill: var(--ui-color-paper);
    stroke: none;
  }
  .topology-segment-header:focus-visible .topology-segment-header-bg {
    stroke: var(--ui-color-focus);
    stroke-width: 2;
  }
  .topology-segment-name {
    fill: var(--ui-color-text);
    font-size: var(--ui-text-sm);
    font-weight: 700;
    pointer-events: none;
  }
  .topology-segment-meta,
  .topology-segment-cidr {
    fill: var(--ui-color-text-muted);
    font: var(--ui-text-xs) var(--ui-font-mono);
    pointer-events: none;
  }
  .topology-self-policy rect {
    fill: var(--ui-color-accent-soft);
    stroke: var(--ui-color-accent);
    stroke-width: 1;
  }
  .topology-self-policy text {
    fill: var(--ui-color-accent);
    font: var(--ui-text-xs) var(--ui-font-mono);
  }
  .topology-structural-edge {
    cursor: default;
  }
  .topology-structural-edge[data-graph-interactive] {
    cursor: pointer;
  }
  .topology-structural-path {
    fill: none;
    stroke: var(
      --structural-stroke,
      var(--structural-color, var(--ui-color-text-muted))
    );
    stroke-dasharray: var(--structural-dash, none);
    stroke-opacity: var(--structural-opacity, 0.8);
    stroke-width: var(--structural-stroke-width, 1.2);
    pointer-events: none;
  }
  .topology-structural-edge.is-selected .topology-structural-path {
    stroke: var(--ui-color-focus);
    stroke-width: 2.5;
  }
  .topology-structural-edge:focus-visible .topology-structural-path {
    stroke: var(--ui-color-focus);
    stroke-width: 3;
  }
  .topology-structural-edge:focus,
  .topology-structural-edge:focus-visible {
    outline: none;
  }
  .topology-structural-label {
    fill: var(--ui-color-text-faint);
    font: var(--ui-text-xs) var(--ui-font-mono);
    pointer-events: none;
    text-anchor: middle;
  }
  .topology-host-glyph {
    cursor: default;
  }
  .topology-host-glyph[data-graph-interactive] {
    cursor: move;
  }
  .topology-host-glyph-card {
    fill: var(--node-card-fill, var(--ui-color-paper));
    fill-opacity: var(--node-card-opacity, 1);
    stroke: var(--node-card-stroke, var(--ui-color-node-host));
    stroke-width: var(--node-card-stroke-width, 1.2);
  }
  .topology-host-glyph.is-selected .topology-host-glyph-card {
    stroke: var(--ui-color-focus);
    stroke-width: 3;
  }
  .topology-host-glyph-name {
    fill: var(--ui-color-text);
    font-size: var(--ui-text-sm);
    font-weight: 700;
    pointer-events: none;
  }
  .topology-host-glyph-count {
    fill: var(--ui-color-text-muted);
    font: var(--ui-text-xs) var(--ui-font-mono);
    pointer-events: none;
  }
  .topology-service {
    cursor: default;
  }
  .topology-service[data-graph-interactive] {
    cursor: move;
  }
  .topology-service-card {
    fill: var(--node-card-fill, var(--ui-color-paper));
    fill-opacity: var(--node-card-opacity, 1);
    stroke: var(--node-card-stroke, var(--ui-color-node-service));
    stroke-width: var(--node-card-stroke-width, 1.2);
  }
  .topology-service.is-selected .topology-service-card {
    stroke: var(--ui-color-focus);
    stroke-width: 3;
  }
  .topology-host-glyph:focus-visible .topology-host-glyph-card,
  .topology-service:focus-visible .topology-service-card {
    stroke: var(--ui-color-focus);
    stroke-width: 3;
  }
  .topology-host-glyph:focus,
  .topology-host-glyph:focus-visible,
  .topology-service:focus,
  .topology-service:focus-visible,
  .topology-context:focus,
  .topology-context:focus-visible,
  .topology-unplaced:focus,
  .topology-unplaced:focus-visible {
    outline: none;
  }
  /*
   * Pinned state carries an icon and an outline. Only the frame of a segment
   * dims, so a dimmed container never compounds with its dimmed members.
   */
  .topology-host-glyph.is-pinned .topology-host-glyph-card,
  .topology-service.is-pinned .topology-service-card,
  .topology-context.is-pinned .topology-context-card {
    stroke: var(--ui-color-accent);
    stroke-width: 2;
    stroke-dasharray: 5 3;
  }
  .topology-host-card.is-pinned :global(.canvas-node-card) {
    stroke: var(--ui-color-accent);
    stroke-width: 2.5;
    stroke-dasharray: 5 3;
  }
  .topology-segment.is-pinned .topology-segment-frame {
    stroke: var(--ui-color-accent);
    stroke-width: 2.5;
    stroke-dasharray: 5 3;
  }
  .topology-host-glyph.is-dimmed,
  .topology-host-card.is-dimmed,
  .topology-service.is-dimmed,
  .topology-context.is-dimmed,
  .topology-unplaced.is-dimmed,
  .topology-structural-edge.is-dimmed,
  .topology-bundle-visual.is-dimmed {
    opacity: var(--topology-dim-opacity);
  }
  .topology-segment.is-dimmed .topology-segment-frame,
  .topology-segment-header.is-dimmed {
    opacity: var(--topology-dim-opacity);
  }
  .topology-service-name {
    fill: var(--ui-color-text);
    font-size: var(--ui-text-sm);
    font-weight: 700;
    pointer-events: none;
  }
  .topology-service-port {
    fill: var(--ui-color-text-muted);
    font: var(--ui-text-xs) var(--ui-font-mono);
    pointer-events: none;
  }
  .topology-connection-handle {
    fill: var(--ui-color-paper);
    stroke: var(--ui-color-accent);
    stroke-width: 2;
    cursor: crosshair;
  }
  .topology-connection-handle:hover {
    fill: var(--ui-color-accent-soft);
  }
  .topology-connection-handle.is-source {
    fill: var(--ui-color-accent-soft);
    stroke: var(--ui-color-preview-edge);
    stroke-dasharray: 4 2;
  }
  .topology-connection-handle:focus {
    outline: none;
  }
  .topology-connection-handle:focus-visible {
    stroke: var(--ui-color-focus);
    stroke-width: 3;
  }
  .topology-pin {
    cursor: pointer;
  }
  .topology-pin rect {
    fill: var(--ui-color-paper);
    stroke: var(--ui-color-border);
    stroke-width: 1.2;
  }
  .topology-pin path {
    fill: none;
    stroke: var(--ui-color-text-secondary);
    stroke-width: 1.4;
    stroke-linejoin: round;
  }
  .topology-pin:hover rect {
    fill: var(--ui-color-accent-soft);
  }
  .topology-pin.is-pinned rect {
    fill: var(--ui-color-accent-soft);
    stroke: var(--ui-color-accent);
  }
  .topology-pin.is-pinned path {
    stroke: var(--ui-color-accent);
    fill: var(--ui-color-accent);
  }
  .topology-pin:focus {
    outline: none;
  }
  .topology-pin:focus-visible rect {
    stroke: var(--ui-color-focus);
    stroke-width: 2.5;
  }
  .topology-anchor-link,
  .topology-anchor-link path {
    pointer-events: none;
  }
  .topology-anchor-link path {
    fill: none;
    stroke: var(--ui-color-text-faint);
    stroke-width: 1.5;
    stroke-dasharray: 2 3;
  }
  .topology-context {
    cursor: default;
  }
  .topology-context[data-graph-interactive] {
    cursor: pointer;
  }
  .topology-context-card {
    fill: var(--ui-color-paper);
    stroke: var(--node-color, var(--ui-color-border));
    stroke-width: 1.5;
    stroke-dasharray: 5 3;
  }
  .topology-context.is-selected .topology-context-card {
    stroke: var(--ui-color-focus);
    stroke-width: 3;
  }
  .topology-context:focus-visible .topology-context-card {
    stroke: var(--ui-color-focus);
    stroke-width: 3;
  }
  .topology-context-title {
    fill: var(--ui-color-text);
    font-size: var(--ui-text-sm);
    font-weight: 700;
    pointer-events: none;
  }
  .topology-context-sub {
    fill: var(--ui-color-text-muted);
    font: var(--ui-text-xs) var(--ui-font-mono);
    pointer-events: none;
  }
  .topology-unplaced {
    cursor: default;
  }
  .topology-unplaced[data-graph-interactive] {
    cursor: pointer;
  }
  .topology-unplaced-card {
    fill: var(--ui-color-warning-bg);
    stroke: var(--ui-color-warning);
    stroke-dasharray: 2 3;
    stroke-width: 1.5;
  }
  .topology-unplaced.is-pending .topology-unplaced-card {
    stroke-dasharray: 6 4;
  }
  .topology-unplaced.is-missing-reference .topology-unplaced-card,
  .topology-unplaced.is-no-placement .topology-unplaced-card {
    stroke: var(--ui-color-danger);
  }
  .topology-unplaced:focus-visible .topology-unplaced-card {
    stroke: var(--ui-color-focus);
    stroke-width: 2.5;
  }
  .topology-unplaced-mark {
    fill: var(--ui-color-warning-text);
    font-size: var(--ui-text-sm);
    font-weight: 700;
    pointer-events: none;
  }
  .topology-unplaced-name {
    fill: var(--ui-color-text);
    font-size: var(--ui-text-sm);
    pointer-events: none;
  }
  .topology-unplaced-reason {
    fill: var(--ui-color-warning-text);
    font: var(--ui-text-xs) var(--ui-font-mono);
    pointer-events: none;
  }
  .topology-host-card.is-pending :global(.canvas-node-card),
  .topology-host-glyph.is-pending .topology-host-glyph-card,
  .topology-service.is-pending .topology-service-card,
  .topology-context.is-pending .topology-context-card {
    stroke: var(--ui-color-warning);
    stroke-dasharray: 6 4;
  }
  .topology-service.is-pending .topology-service-card,
  .topology-context.is-pending .topology-context-card {
    fill: var(--ui-color-warning-bg);
  }
  .topology-host-card.is-placement-issue :global(.canvas-node-card),
  .topology-service.is-placement-issue .topology-service-card,
  .topology-context.is-placement-issue .topology-context-card,
  .topology-host-glyph.is-placement-issue .topology-host-glyph-card {
    stroke: var(--ui-color-danger);
    stroke-dasharray: 2 3;
  }
  .topology-connection-preview {
    fill: none;
    stroke: var(--ui-color-preview-edge);
    stroke-width: 2;
    stroke-dasharray: 6 4;
    pointer-events: none;
  }
  .topology-status {
    position: absolute;
    bottom: var(--ui-space-3);
    left: var(--ui-space-3);
    display: flex;
    flex-direction: column;
    gap: var(--ui-space-1);
    align-items: flex-start;
  }
  .topology-status-item {
    margin: 0;
    padding: 0.3125rem var(--ui-space-2);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
    font-size: var(--ui-text-xs);
  }
  .topology-status-item.is-pending {
    border-color: var(--ui-color-warning);
    color: var(--ui-color-warning-text);
  }
  .topology-status-item.is-stale {
    border-color: var(--ui-color-danger);
    color: var(--ui-color-danger);
  }
  .topology-status-item.is-draft {
    border-color: var(--ui-color-preview-edge);
    color: var(--ui-color-preview-edge);
  }
  .topology-status-item.is-placement {
    background: var(--ui-color-warning-bg);
    border-color: var(--ui-color-warning);
    color: var(--ui-color-warning-text);
  }
  .topology-status-item.is-connection {
    border-color: var(--ui-color-preview-edge);
    color: var(--ui-color-preview-edge);
  }
  .topology-controls {
    position: absolute;
    right: var(--ui-space-3);
    bottom: var(--ui-space-3);
    display: flex;
    align-items: stretch;
    overflow: hidden;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
  }
  .topology-controls button,
  .topology-controls output {
    min-width: 2.75rem;
    min-height: 2.75rem;
    border: 0;
    background: transparent;
    color: var(--ui-color-text);
    font: inherit;
  }
  .topology-controls button {
    display: grid;
    place-items: center;
    font-size: 1.25rem;
  }
  .topology-controls button:hover {
    background: var(--ui-color-accent-soft);
  }
  .topology-controls output {
    display: grid;
    place-items: center;
    border-inline: 1px solid var(--ui-color-border-soft);
    font-family: var(--ui-font-mono);
    font-variant-numeric: tabular-nums;
  }
  :global(.dashboard-menu-separator) {
    height: 1px;
    margin: var(--ui-space-1) 0;
    background: var(--ui-color-border-soft);
  }
  @media (max-width: 35rem) {
    .topology-status {
      max-width: calc(100% - 8rem);
      left: var(--ui-space-2);
      bottom: var(--ui-space-2);
    }
    .topology-controls {
      right: var(--ui-space-2);
      bottom: var(--ui-space-2);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .topology-surface {
      transition: none;
    }
  }
  @media (forced-colors: active) {
    .topology-surface {
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
    .topology-world.is-stale {
      filter: none;
    }
    .topology-status-item,
    .topology-controls {
      border-color: CanvasText;
      background: Canvas;
      color: CanvasText;
    }
    .topology-controls output {
      border-color: CanvasText;
    }
  }
</style>
