<script lang="ts">
  import type { GraphContract } from "../../../contracts.generated/graph";
  import type { GraphProjectionOperationalFlow } from "../../../contracts.generated/dashboard/graph";

  import type { DashboardApi } from "../../dashboard-api";
  import type { EditableGraphDocument } from "../EditableGraphDocument.svelte";
  import { type ZonePosition } from "./NetworkCanvasLayout";
  import { projectNetwork } from "./NetworkCanvasProjection";
  import {
    clampZoom,
    formatWorldTransform,
    isActivationKey,
    screenToWorld,
    ZOOM_STEP,
  } from "../canvas/canvasState";
  import type {
    CanvasEdgeAppearance,
    CanvasNodeAppearance,
  } from "../canvas/appearance";
  import type {
    NetworkOperationalFlow,
    NetworkSegmentLink,
  } from "./NetworkCanvasProjection";

  const COLLAPSED_RADIUS = { x: 130, y: 72 };
  const EXPANDED_RADIUS = { x: 235, y: 155 };
  const HOST_WIDTH = 128;
  const HOST_BASE_HEIGHT = 52;
  const HOST_DETAIL_TOP = 8;
  const SERVICE_ROW_HEIGHT = 24;
  const CVE_ROW_HEIGHT = 18;
  const DRAG_THRESHOLD = 4;

  interface Props {
    document?: EditableGraphDocument;
    api?: DashboardApi;
    graph?: GraphContract;
    operationalFlows?: readonly GraphProjectionOperationalFlow[];
    selectedNodeId?: string;
    selectedEdgeId?: string;
    onSelectNode?: (nodeId: string) => void;
    onSelectEdge?: (edgeId: string) => void;
    onGraphChange?: (graph: GraphContract) => void;
    hostAppearance?: (hostId: string) => CanvasNodeAppearance | undefined;
    policyLinkAppearance?: (
      link: NetworkSegmentLink,
    ) => CanvasEdgeAppearance | undefined;
    operationalFlowAppearance?: (
      flow: NetworkOperationalFlow,
    ) => CanvasEdgeAppearance | undefined;
    onArrangeNetwork?: () => void;
  }

  interface DisplayZone {
    id: string;
    name: string;
    cidr?: string | null;
    node?: { id: string };
    hosts: (typeof projection.hosts)[number][];
    position: ZonePosition;
    radius: { x: number; y: number };
  }

  let {
    document = undefined,
    api = undefined,
    graph = undefined,
    operationalFlows = undefined,
    selectedNodeId = undefined,
    selectedEdgeId = undefined,
    onSelectNode = undefined,
    onSelectEdge = undefined,
    onGraphChange = undefined,
    hostAppearance = undefined,
    policyLinkAppearance = undefined,
    operationalFlowAppearance = undefined,
    onArrangeNetwork = undefined,
  }: Props = $props();
  let effectiveGraph = $derived(graph ?? document?.graph);
  let isHeatmapMode = $derived(Boolean(graph));
  let viewport = $state({ width: 0, height: 0 });
  let view = $state({ zoom: 100, pan: { x: 0, y: 0 } });
  let expandedSegmentIds = $state(new Set<string>());
  let expandedHostIds = $state(new Set<string>());
  let panDrag = $state<{
    pointerId: number;
    x: number;
    y: number;
    pan: ZonePosition;
  }>();
  let nodeDrag = $state<{
    pointerId: number;
    element: SVGElement;
    nodeIds: string[];
    x: number;
    y: number;
    moved: boolean;
  }>();
  let status = $state("");
  let serverFlows = $state<readonly GraphProjectionOperationalFlow[]>();
  let projectedRevisionId = $state<string | null>(null);
  let projectionError = $state("");

  let projection = $derived.by(() => {
    if (!effectiveGraph) {
      return {
        hosts: [],
        segments: [],
        segmentLinks: [],
        operationalFlows: [],
      };
    }
    if (operationalFlows) {
      return projectNetwork(effectiveGraph, operationalFlows);
    }
    return projectNetwork(
      effectiveGraph,
      document?.loadedRevisionId === projectedRevisionId
        ? serverFlows
        : undefined,
    );
  });
  let zones = $derived.by<DisplayZone[]>(() =>
    projection.segments.map((segment) => {
      const expanded = expandedSegmentIds.has(segment.id);
      return {
        ...segment,
        position: { ...segment.position },
        radius: expanded ? expandedRadius(segment) : COLLAPSED_RADIUS,
      };
    }),
  );
  let zoneById = $derived(new Map(zones.map((zone) => [zone.id, zone])));
  let hostById = $derived(
    new Map(projection.hosts.map((host) => [host.id, host])),
  );
  let visibleHosts = $derived(
    projection.hosts.filter((host) => expandedSegmentIds.has(host.segmentId)),
  );
  let hostPositions = $derived(
    new Map(
      visibleHosts.map((host) => [
        host.id,
        { x: host.node.view_data.x_pos, y: host.node.view_data.y_pos },
      ]),
    ),
  );
  let effectiveSelectedNodeId = $derived(
    selectedNodeId ??
      (document?.canvasSelection.kind === "node"
        ? document.canvasSelection.nodeId
        : undefined),
  );
  let effectiveSelectedEdgeId = $derived(
    selectedEdgeId ??
      (document?.canvasSelection.kind === "edge"
        ? document.canvasSelection.edgeId
        : undefined),
  );
  let selectionNode = $derived(
    effectiveGraph?.nodes.find((node) => node.id === effectiveSelectedNodeId),
  );
  let selectedFlowHostId = $derived.by(() => {
    if (selectionNode?.type === "Host") return selectionNode.id;
    if (selectionNode?.type === "Service")
      return projection.hosts.find((host) =>
        host.services.some((service) => service.node.id === selectionNode!.id),
      )?.id;
    if (!document) return undefined;
    const selection = document.selection;
    if (selection?.type === "Host") return selection.id;
    if (selection?.type === "Service")
      return projection.hosts.find((host) =>
        host.services.some((service) => service.node.id === selection.id),
      )?.id;
    return undefined;
  });
  let visibleFlows = $derived(
    projection.operationalFlows.filter(
      (flow) =>
        selectedFlowHostId &&
        (flow.sourceId === selectedFlowHostId ||
          flow.targetId === selectedFlowHostId) &&
        hostPositions.has(flow.sourceId) &&
        hostPositions.has(flow.targetId),
    ),
  );
  let visibleFlowIds = $derived(new Set(visibleFlows.map((flow) => flow.id)));
  let selectedHost = $derived(
    selectionNode?.type === "Host"
      ? selectionNode
      : document?.selection?.type === "Host"
        ? document.selection
        : undefined,
  );
  let projectionStale = $derived(
    !isHeatmapMode &&
      document !== undefined &&
      document.loadedRevisionId !== null &&
      (document.isDirty || document.loadedRevisionId !== projectedRevisionId),
  );
  let transform = $derived(formatWorldTransform(view));
  let flowArrowId = $props.id();

  $effect(() => {
    if (isHeatmapMode || operationalFlows) return;
    const revisionId = document?.loadedRevisionId;
    if (!revisionId || revisionId === projectedRevisionId || document?.isDirty)
      return;
    let active = true;
    void api
      ?.fetchGraphProjection(revisionId)
      .then((reply) => {
        if (!active || document?.loadedRevisionId !== revisionId) return;
        if (reply?.status === "ok") {
          serverFlows = reply.operational_flows;
          projectedRevisionId = revisionId;
          projectionError = "";
        } else {
          projectionError = "Reachability projection unavailable.";
        }
      })
      .catch(() => {
        if (active) projectionError = "Reachability projection unavailable.";
      });
    return () => {
      active = false;
    };
  });

  function zoneBoundary(
    source: DisplayZone,
    target: DisplayZone,
  ): [ZonePosition, ZonePosition] {
    const dx = target.position.x - source.position.x;
    const dy = target.position.y - source.position.y;
    const distance = Math.hypot(dx, dy);
    const unit = distance
      ? { x: dx / distance, y: dy / distance }
      : { x: 1, y: 0 };
    const extent = (zone: DisplayZone) =>
      1 /
      Math.sqrt((unit.x / zone.radius.x) ** 2 + (unit.y / zone.radius.y) ** 2);
    const sourceExtent = extent(source);
    const targetExtent = extent(target);
    return [
      {
        x: source.position.x + unit.x * sourceExtent,
        y: source.position.y + unit.y * sourceExtent,
      },
      {
        x: target.position.x - unit.x * targetExtent,
        y: target.position.y - unit.y * targetExtent,
      },
    ];
  }

  function serviceDetailHeight(
    service: (typeof projection.hosts)[number]["services"][number],
  ): number {
    return SERVICE_ROW_HEIGHT + service.vulnerabilities.length * CVE_ROW_HEIGHT;
  }

  function hostCardHeight(host: (typeof projection.hosts)[number]): number {
    return expandedHostIds.has(host.id)
      ? HOST_BASE_HEIGHT +
          HOST_DETAIL_TOP +
          host.services.reduce(
            (height, service) => height + serviceDetailHeight(service),
            0,
          ) +
          HOST_DETAIL_TOP
      : HOST_BASE_HEIGHT;
  }

  function serviceOffset(
    services: (typeof projection.hosts)[number]["services"],
    serviceId: string,
  ): number {
    return services
      .slice(
        0,
        services.findIndex((service) => service.node.id === serviceId),
      )
      .reduce((offset, service) => offset + serviceDetailHeight(service), 0);
  }

  function expandedRadius(zone: Pick<DisplayZone, "position" | "hosts">): {
    x: number;
    y: number;
  } {
    let maxX = 0;
    let maxY = 0;
    for (const host of zone.hosts) {
      maxX = Math.max(
        maxX,
        Math.abs(host.node.view_data.x_pos - zone.position.x) + HOST_WIDTH / 2,
      );
      maxY = Math.max(
        maxY,
        Math.abs(host.node.view_data.y_pos - zone.position.y) +
          hostCardHeight(host) / 2,
      );
    }
    return {
      x: Math.max(EXPANDED_RADIUS.x, (maxX + 12) * Math.SQRT2),
      y: Math.max(EXPANDED_RADIUS.y, (maxY + 12) * Math.SQRT2),
    };
  }

  function toggleZone(segmentId: string): void {
    const next = new Set(expandedSegmentIds);
    if (next.has(segmentId)) next.delete(segmentId);
    else next.add(segmentId);
    expandedSegmentIds = next;
  }

  function toggleHostDetail(hostId: string): void {
    const next = new Set(expandedHostIds);
    if (next.has(hostId)) next.delete(hostId);
    else next.add(hostId);
    expandedHostIds = next;
  }

  function expandAllZones(): void {
    expandedSegmentIds = new Set(projection.segments.map((zone) => zone.id));
  }

  function collapseAllZones(): void {
    expandedSegmentIds = new Set();
    expandedHostIds = new Set();
  }

  function startPan(event: PointerEvent): void {
    const surface = event.currentTarget as SVGSVGElement;
    if (event.target !== surface || event.button !== 0 || !event.isPrimary)
      return;
    surface.setPointerCapture(event.pointerId);
    panDrag = {
      pointerId: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      pan: { ...view.pan },
    };
  }

  function movePan(event: PointerEvent): void {
    if (!panDrag || panDrag.pointerId !== event.pointerId) return;
    view.pan = {
      x: panDrag.pan.x + event.clientX - panDrag.x,
      y: panDrag.pan.y + event.clientY - panDrag.y,
    };
  }

  function endPan(event: PointerEvent): void {
    if (!panDrag || panDrag.pointerId !== event.pointerId) return;
    const surface = event.currentTarget as SVGSVGElement;
    if (surface.hasPointerCapture(event.pointerId))
      surface.releasePointerCapture(event.pointerId);
    panDrag = undefined;
  }

  function selectNode(nodeId: string): void {
    if (onSelectNode) onSelectNode(nodeId);
    else document?.selectNode(nodeId);
  }

  function selectEdge(edgeId: string): void {
    if (onSelectEdge) onSelectEdge(edgeId);
    else document?.selectEdge(edgeId);
  }

  function updateGraph(updater: (graph: GraphContract) => GraphContract): void {
    if (onGraphChange && effectiveGraph) {
      onGraphChange(updater(effectiveGraph));
      return;
    }
    if (document && effectiveGraph) {
      document.graph = updater(effectiveGraph);
    }
  }

  function startNodeDrag(
    event: PointerEvent,
    nodeId: string,
    nodeIds: string[] = [nodeId],
  ): void {
    if (event.button !== 0 || !event.isPrimary) return;
    event.stopPropagation();
    const element = event.currentTarget as SVGElement;
    element.setPointerCapture(event.pointerId);
    selectNode(nodeId);
    nodeDrag = {
      pointerId: event.pointerId,
      element,
      nodeIds,
      x: event.clientX,
      y: event.clientY,
      moved: false,
    };
  }

  function moveNodeDrag(event: PointerEvent): void {
    if (!nodeDrag || nodeDrag.pointerId !== event.pointerId) return;
    const dx = (event.clientX - nodeDrag.x) / (view.zoom / 100);
    const dy = (event.clientY - nodeDrag.y) / (view.zoom / 100);
    if (Math.hypot(dx, dy) < DRAG_THRESHOLD / (view.zoom / 100)) return;
    nodeDrag.moved = true;
    nodeDrag.x = event.clientX;
    nodeDrag.y = event.clientY;
    const ids = new Set(nodeDrag.nodeIds);
    updateGraph((graph) => ({
      ...graph,
      nodes: graph.nodes.map((node) =>
        ids.has(node.id)
          ? {
              ...node,
              view_data: {
                ...node.view_data,
                x_pos: node.view_data.x_pos + dx,
                y_pos: node.view_data.y_pos + dy,
              },
            }
          : node,
      ),
    }));
  }

  function endNodeDrag(event: PointerEvent): void {
    if (!nodeDrag || nodeDrag.pointerId !== event.pointerId) return;
    if (nodeDrag.element.hasPointerCapture(event.pointerId))
      nodeDrag.element.releasePointerCapture(event.pointerId);
    nodeDrag = undefined;
  }

  function cardEdge(
    source: ZonePosition,
    target: ZonePosition,
    height: number,
  ): ZonePosition {
    const dx = target.x - source.x;
    const dy = target.y - source.y;
    const ratio = Math.max(
      Math.abs(dx) / (HOST_WIDTH / 2),
      Math.abs(dy) / (height / 2),
      1,
    );
    return { x: source.x + dx / ratio, y: source.y + dy / ratio };
  }

  function flowPath(flow: (typeof visibleFlows)[number]): {
    d: string;
    label: ZonePosition;
  } {
    const source = hostPositions.get(flow.sourceId)!;
    const target = hostPositions.get(flow.targetId)!;
    if (flow.sourceId === flow.targetId) {
      const x = source.x + HOST_WIDTH / 2;
      return {
        d: `M ${x} ${source.y} C ${x + 56} ${source.y - 56} ${x + 56} ${source.y + 56} ${x} ${source.y + 20}`,
        label: { x: x + 56, y: source.y },
      };
    }
    const sourceEdge = cardEdge(
      source,
      target,
      hostCardHeight(hostById.get(flow.sourceId)!),
    );
    const targetEdge = cardEdge(
      target,
      source,
      hostCardHeight(hostById.get(flow.targetId)!),
    );
    const dx = targetEdge.x - sourceEdge.x;
    const dy = targetEdge.y - sourceEdge.y;
    const distance = Math.hypot(dx, dy) || 1;
    const reverseVisible = visibleFlowIds.has(
      `${flow.targetId}:${flow.sourceId}`,
    );
    const offset = reverseVisible ? 18 : 0;
    const control = {
      x: (sourceEdge.x + targetEdge.x) / 2 - (dy / distance) * offset,
      y: (sourceEdge.y + targetEdge.y) / 2 + (dx / distance) * offset,
    };
    return {
      d: `M ${sourceEdge.x} ${sourceEdge.y} Q ${control.x} ${control.y} ${targetEdge.x} ${targetEdge.y}`,
      label: control,
    };
  }

  function setZoom(zoom: number, anchor: ZonePosition): void {
    const nextZoom = clampZoom(zoom);
    const graphPoint = screenToWorld(anchor, view);
    const nextScale = nextZoom / 100;
    view = {
      zoom: nextZoom,
      pan: {
        x: anchor.x - graphPoint.x * nextScale,
        y: anchor.y - graphPoint.y * nextScale,
      },
    };
  }

  function zoomBy(delta: number): void {
    setZoom(view.zoom + delta, {
      x: viewport.width / 2,
      y: viewport.height / 2,
    });
  }

  function zoomAtCursor(event: WheelEvent): void {
    event.preventDefault();
    const bounds = (
      event.currentTarget as SVGSVGElement
    ).getBoundingClientRect();
    setZoom(view.zoom + (event.deltaY < 0 ? ZOOM_STEP : -ZOOM_STEP), {
      x: event.clientX - bounds.left,
      y: event.clientY - bounds.top,
    });
  }

  function fit(): void {
    if (!zones.length || !viewport.width || !viewport.height) return;
    const left = Math.min(
      ...zones.map((zone) => zone.position.x - zone.radius.x),
    );
    const right = Math.max(
      ...zones.map((zone) => zone.position.x + zone.radius.x),
    );
    const top = Math.min(
      ...zones.map((zone) => zone.position.y - zone.radius.y),
    );
    const bottom = Math.max(
      ...zones.map((zone) => zone.position.y + zone.radius.y),
    );
    const zoom = clampZoom(
      Math.min(
        viewport.width / (right - left),
        viewport.height / (bottom - top),
      ) * 90,
    );
    const scale = zoom / 100;
    view = {
      zoom,
      pan: {
        x: viewport.width / 2 - ((left + right) / 2) * scale,
        y: viewport.height / 2 - ((top + bottom) / 2) * scale,
      },
    };
  }

  function resetView(): void {
    view = { zoom: 100, pan: { x: 0, y: 0 } };
  }

  async function createContainment(
    segmentId: string,
    hostId: string,
  ): Promise<void> {
    const host = hostById.get(hostId);
    if (!host || host.segmentId !== "unassigned") {
      status = "A host can belong to only one segment.";
      return;
    }
    if (!api || !document) {
      status = "Not available in this view.";
      return;
    }
    const reply = await api.createConnectionDraft({
      relationship_type: "Contains",
      source_id: segmentId,
      source_type: "NetworkSegment",
      source_is_from: true,
      target_id: hostId,
      target_type: "Host",
    });
    if (reply.status === "ok" && reply.edge) {
      document.createConnection(reply.edge);
      status = "";
    } else {
      status = "Could not assign host to segment.";
    }
  }

  function assignSelectedHost(event: Event): void {
    const select = event.currentTarget as HTMLSelectElement;
    const segmentId = select.value;
    select.value = "";
    if (segmentId && selectedHost)
      void createContainment(segmentId, selectedHost.id);
  }

  async function addNode(type: "Host" | "NetworkSegment"): Promise<void> {
    const position = screenToWorld(
      { x: viewport.width / 2, y: viewport.height / 2 },
      view,
    );
    if (api && document) {
      const reply = await api.createNodeDraft({
        node_type: type,
        x_pos: position.x,
        y_pos: position.y,
      });
      if (reply.status === "ok" && reply.node) document.addNode(reply.node);
      return;
    }
    if (effectiveGraph && onGraphChange) {
      // Local draft for heatmap (no server): synthesize minimal node.
      const id = crypto.randomUUID();
      const data =
        type === "Host"
          ? { name: "Host" }
          : { name: "Segment", cidr: null as string | null };
      onGraphChange({
        ...effectiveGraph,
        nodes: [
          ...effectiveGraph.nodes,
          {
            id,
            type,
            data: data as never,
            view_data: { x_pos: position.x, y_pos: position.y },
          },
        ],
      });
    }
  }

  function activateKey(event: KeyboardEvent, action: () => void): void {
    if (!isActivationKey(event.key)) return;
    event.preventDefault();
    action();
  }
</script>

<section class="network-canvas" aria-label="Network canvas">
  <div class="network-toolbar">
    {#if !isHeatmapMode}
      <button type="button" onclick={() => addNode("Host")}>Add host</button>
      <button type="button" onclick={() => addNode("NetworkSegment")}
        >Add segment</button
      >
    {/if}
    {#if onArrangeNetwork}
      <button type="button" onclick={onArrangeNetwork}>Arrange network</button>
    {/if}
    <button type="button" onclick={expandAllZones}>Expand all zones</button>
    <button type="button" onclick={collapseAllZones}>Collapse all zones</button>
    {#if selectedHost && !isHeatmapMode}
      <select
        aria-label="Assign selected host to a segment"
        onchange={assignSelectedHost}
      >
        <option value="">Assign selected host</option>
        {#each projection.segments as segment (segment.id)}
          {#if segment.node}
            <option value={segment.id}>{segment.name}</option>
          {/if}
        {/each}
      </select>
    {/if}
    <span
      >{projection.hosts.length} hosts · {projection.segments.length} zones</span
    >
    {#if status}
      <span class="network-toolbar-status" role="status" aria-live="polite"
        >{status}</span
      >
    {/if}
  </div>
  {#if projectionError}
    <div class="network-projection-notice" role="status" aria-live="polite">
      {projectionError}
    </div>
  {:else if projectionStale}
    <div class="network-projection-notice" role="status" aria-live="polite">
      Reachability flows are stale. Save to refresh.
    </div>
  {/if}

  <svg
    class="network-surface"
    role="group"
    viewBox={`0 0 ${viewport.width} ${viewport.height}`}
    aria-label="Network topology. Drag blank space to pan."
    bind:clientWidth={viewport.width}
    bind:clientHeight={viewport.height}
    onpointerdown={startPan}
    onpointermove={(event) => {
      movePan(event);
      moveNodeDrag(event);
    }}
    onpointerup={(event) => {
      endPan(event);
      endNodeDrag(event);
    }}
    onpointercancel={(event) => {
      endPan(event);
      endNodeDrag(event);
    }}
    onwheel={zoomAtCursor}
  >
    <defs>
      <marker
        id={flowArrowId}
        markerWidth="6"
        markerHeight="6"
        refX="5"
        refY="3"
        orient="auto"
      >
        <path d="M 0 0 L 6 3 L 0 6 z" fill="var(--ui-color-node-service)" />
      </marker>
    </defs>
    <g {transform}>
      {#each projection.segmentLinks as link (link.id)}
        {@const source = zoneById.get(link.sourceId)}
        {@const target = zoneById.get(link.targetId)}
        {#if source && target}
          {@const boundary = zoneBoundary(source, target)}
          {@const linkHeat = policyLinkAppearance?.(link)}
          <g
            class="network-policy-link"
            data-testid="policy-link"
            role="button"
            tabindex="0"
            aria-label="Segment reachability"
            onclick={() => selectEdge(link.edgeIds[0]!)}
            onkeydown={(event) =>
              activateKey(event, () => selectEdge(link.edgeIds[0]!))}
          >
            <path
              d={`M ${boundary[0].x} ${boundary[0].y} L ${boundary[1].x} ${boundary[1].y}`}
              style:stroke={linkHeat?.stroke}
              style:stroke-width={linkHeat?.strokeWidth}
              style:opacity={linkHeat?.opacity}
            />
          </g>
        {/if}
      {/each}

      {#each zones as zone (zone.id)}
        {@const selected = effectiveSelectedNodeId === zone.id}
        {@const expanded = expandedSegmentIds.has(zone.id)}
        {@const glyphX = zone.position.x + zone.radius.x * 0.82}
        {@const glyphY = zone.position.y - zone.radius.y * 0.57}
        <g
          class={["network-zone", selected && "selected"]}
          data-testid="network-zone"
          role="group"
          aria-label={`${zone.name} zone`}
          onpointerdown={(event) =>
            zone.node &&
            startNodeDrag(event, zone.id, [
              zone.id,
              ...zone.hosts.map((host) => host.id),
            ])}
        >
          <ellipse
            data-testid="zone-oval"
            data-zone-id={zone.id}
            cx={zone.position.x}
            cy={zone.position.y}
            rx={zone.radius.x}
            ry={zone.radius.y}
          />
          <text
            class="network-zone-name"
            x={zone.position.x}
            y={zone.position.y - zone.radius.y + 28}>{zone.name}</text
          >
          <text
            class="network-zone-meta"
            x={zone.position.x}
            y={zone.position.y - zone.radius.y + 48}
            >{zone.hosts.length} hosts{zone.cidr ? ` · ${zone.cidr}` : ""}</text
          >
          <g
            class="network-zone-glyph"
            data-testid="zone-glyph"
            role="button"
            tabindex="0"
            aria-label={expanded
              ? `Collapse ${zone.name} zone in diagram`
              : `Expand ${zone.name} zone in diagram`}
            onpointerdown={(event) => event.stopPropagation()}
            onclick={() => toggleZone(zone.id)}
            onkeydown={(event) => activateKey(event, () => toggleZone(zone.id))}
          >
            <circle cx={glyphX} cy={glyphY} r="12" />
            <path
              d={`M ${glyphX - 5} ${glyphY} H ${glyphX + 5}${expanded ? "" : ` M ${glyphX} ${glyphY - 5} V ${glyphY + 5}`}`}
            />
            <text x={glyphX + 18} y={glyphY + 4}>{expanded ? "−" : "+"}</text>
          </g>
        </g>
      {/each}

      {#each visibleFlows as flow (flow.id)}
        {@const path = flowPath(flow)}
        {@const flowHeat = operationalFlowAppearance?.(flow)}
        <g
          class="network-operational-flow"
          role="img"
          aria-label={`Operational flow from ${flow.sourceName} to ${flow.targetName}: ${flow.count} ${flow.count === 1 ? "flow" : "flows"} (${flow.serviceNames.join(", ")})`}
        >
          <path
            d={path.d}
            marker-end={`url(#${flowArrowId})`}
            style:stroke={flowHeat?.stroke}
            style:stroke-width={flowHeat?.strokeWidth}
            style:opacity={flowHeat?.opacity}
          />
          <text x={path.label.x} y={path.label.y - 6}
            >{flow.serviceNames.length === 1
              ? flow.serviceNames[0]
              : `${flow.count} flows`}</text
          >
        </g>
      {/each}
      {#each zones as zone (zone.id)}
        {#if expandedSegmentIds.has(zone.id)}
          {#each zone.hosts as host (host.id)}
            {@const position = hostPositions.get(host.id)!}
            {@const height = hostCardHeight(host)}
            {@const detailExpanded = expandedHostIds.has(host.id)}
            {@const selected = effectiveSelectedNodeId === host.id}
            {@const heat = hostAppearance?.(host.id)}
            <g
              class={["network-host", selected && "selected"]}
              data-testid="host-node"
              role="group"
              aria-label={`Host ${host.node.data.name}`}
              data-host-id={host.id}
              data-card-height={height}
              transform={`translate(${position.x - HOST_WIDTH / 2} ${position.y - height / 2})`}
              onpointerdown={(event) => startNodeDrag(event, host.id)}
            >
              <rect
                width={HOST_WIDTH}
                {height}
                rx="7"
                style:fill={heat?.cardFill}
                style:stroke={heat?.cardStroke}
                style:stroke-width={heat?.cardStrokeWidth}
                style:opacity={heat?.cardOpacity}
              />
              <text x="10" y="22">{host.node.data.name}</text>
              <text class="network-host-meta" x="10" y="40"
                >{host.services.length} services</text
              >
              {#if host.services.length}
                <g
                  class="network-host-glyph"
                  data-testid="host-glyph"
                  role="button"
                  tabindex="0"
                  aria-label={detailExpanded
                    ? `Collapse details for host ${host.node.data.name}`
                    : `Expand details for host ${host.node.data.name}`}
                  onpointerdown={(event) => event.stopPropagation()}
                  onclick={(event) => {
                    event.stopPropagation();
                    toggleHostDetail(host.id);
                  }}
                  onkeydown={(event) => {
                    event.stopPropagation();
                    activateKey(event, () => toggleHostDetail(host.id));
                  }}
                >
                  <circle cx={HOST_WIDTH - 16} cy="16" r="8" />
                  <path
                    d={`M ${HOST_WIDTH - 20} 16 H ${HOST_WIDTH - 12}${detailExpanded ? "" : ` M ${HOST_WIDTH - 16} 12 V 20`}`}
                  />
                </g>
              {/if}
              {#if detailExpanded}
                {#each host.services as service (service.node.id)}
                  {@const serviceY =
                    HOST_BASE_HEIGHT +
                    HOST_DETAIL_TOP +
                    serviceOffset(host.services, service.node.id)}
                  <g
                    class="network-service-row"
                    data-testid="service-row"
                    role="button"
                    tabindex="0"
                    aria-label={`Service ${service.node.data.name}`}
                    onclick={(event) => {
                      event.stopPropagation();
                      selectNode(service.node.id);
                    }}
                    onkeydown={(event) => {
                      event.stopPropagation();
                      activateKey(event, () => selectNode(service.node.id));
                    }}
                  >
                    <rect
                      x="8"
                      y={serviceY}
                      width={HOST_WIDTH - 16}
                      height={SERVICE_ROW_HEIGHT}
                      rx="3"
                    />
                    <text x="14" y={serviceY + 16}
                      >{service.node.data.name}:{service.node.data.port}</text
                    >
                  </g>
                  {#each service.vulnerabilities as vulnerability, index (vulnerability.id)}
                    {@const vulnerabilityY =
                      serviceY + SERVICE_ROW_HEIGHT + index * CVE_ROW_HEIGHT}
                    <g
                      class="network-vulnerability-row"
                      data-testid="cve-row"
                      role="button"
                      tabindex="0"
                      aria-label={`CVE ${vulnerability.data.identifier}`}
                      onclick={(event) => {
                        event.stopPropagation();
                        selectNode(vulnerability.id);
                      }}
                      onkeydown={(event) => {
                        event.stopPropagation();
                        activateKey(event, () => selectNode(vulnerability.id));
                      }}
                    >
                      <rect
                        x="12"
                        y={vulnerabilityY}
                        width={HOST_WIDTH - 24}
                        height={CVE_ROW_HEIGHT}
                        rx="3"
                      />
                      <text x="18" y={vulnerabilityY + 13}
                        >{vulnerability.data.identifier}</text
                      >
                    </g>
                  {/each}
                {/each}
              {/if}
            </g>
          {/each}
        {/if}
      {/each}
    </g>
  </svg>

  <div class="network-controls" aria-label="Network canvas controls">
    <button
      type="button"
      aria-label="Zoom out"
      onclick={() => zoomBy(-ZOOM_STEP)}>−</button
    >
    <output aria-label="Zoom level">{view.zoom}%</output>
    <button type="button" aria-label="Zoom in" onclick={() => zoomBy(ZOOM_STEP)}
      >+</button
    >
    <button type="button" onclick={fit}>Fit</button>
    <button type="button" onclick={resetView}>Reset</button>
  </div>

  <details class="network-outline">
    <summary>Network outline</summary>
    <ul>
      {#each zones as zone (zone.id)}
        {@const expanded = expandedSegmentIds.has(zone.id)}
        <li>
          {#if zone.node}
            <button type="button" onclick={() => selectNode(zone.id)}
              >Select {zone.name}</button
            >
          {/if}
          <button
            type="button"
            aria-expanded={expanded}
            onclick={() => toggleZone(zone.id)}
            >{expanded ? "Collapse" : "Expand"} {zone.name}</button
          >
          {#if expanded}
            <ul>
              {#each zone.hosts as host (host.id)}
                <li>
                  <button type="button" onclick={() => selectNode(host.id)}
                    >Select host {host.node.data.name}</button
                  >
                  {#if host.services.length}
                    <button
                      type="button"
                      aria-expanded={expandedHostIds.has(host.id)}
                      onclick={() => toggleHostDetail(host.id)}
                      >{expandedHostIds.has(host.id) ? "Collapse" : "Expand"} details
                      for {host.node.data.name}</button
                    >
                  {/if}
                  {#if expandedHostIds.has(host.id)}
                    <ul>
                      {#each host.services as service (service.node.id)}
                        <li>
                          <button
                            type="button"
                            onclick={() => selectNode(service.node.id)}
                            >Select service {service.node.data.name}</button
                          >
                          {#if service.vulnerabilities.length}
                            <ul>
                              {#each service.vulnerabilities as vulnerability (vulnerability.id)}
                                <li>
                                  <button
                                    type="button"
                                    onclick={() => selectNode(vulnerability.id)}
                                    >Select CVE {vulnerability.data
                                      .identifier}</button
                                  >
                                </li>
                              {/each}
                            </ul>
                          {/if}
                        </li>
                      {/each}
                    </ul>
                  {/if}
                </li>
              {/each}
            </ul>
          {/if}
        </li>
      {/each}
    </ul>
  </details>
</section>

<style>
  .network-canvas {
    position: relative;
    height: 100%;
    min-height: 0;
    overflow: hidden;
    background: var(--ui-color-canvas);
  }
  .network-toolbar,
  .network-controls {
    position: absolute;
    z-index: 1;
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--ui-space-2);
    padding: 0.375rem 0.5rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
    font-size: var(--ui-text-xs);
  }
  .network-toolbar {
    top: calc(var(--ui-space-3) + 2.5rem);
    left: var(--ui-space-3);
    max-inline-size: calc(100% - 2 * var(--ui-space-3));
  }
  .network-toolbar button,
  .network-controls button,
  .network-toolbar select {
    border: 0;
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-accent-soft);
    color: var(--ui-color-text);
    padding: 0.25rem 0.5rem;
  }
  .network-toolbar-status {
    color: var(--ui-color-text-secondary);
  }
  .network-projection-notice {
    position: absolute;
    z-index: 1;
    top: calc(var(--ui-space-3) + 5rem);
    left: 50%;
    transform: translateX(-50%);
    padding: 0.25rem 0.5rem;
    border: 1px solid var(--ui-color-warning);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-warning-bg);
    color: var(--ui-color-warning-text);
    font-size: var(--ui-text-xs);
    box-shadow: var(--ui-shadow-md);
  }
  .network-surface {
    display: block;
    width: 100%;
    height: 100%;
    touch-action: none;
    background-image: radial-gradient(
      var(--ui-color-border) 1px,
      transparent 1px
    );
    background-size: 20px 20px;
    cursor: grab;
  }
  .network-surface:active {
    cursor: grabbing;
  }
  .network-policy-link {
    cursor: pointer;
  }
  .network-policy-link path {
    fill: none;
    stroke: var(--ui-color-preview-edge);
    stroke-width: 2;
  }
  .network-zone {
    cursor: pointer;
  }
  .network-zone > ellipse {
    fill: var(--ui-color-accent-soft);
    stroke: var(--ui-color-accent);
    stroke-width: 2;
  }
  .network-zone.selected > ellipse,
  .network-host.selected > rect {
    stroke: var(--ui-color-focus);
    stroke-width: 3;
  }
  .network-zone-name,
  .network-zone-meta {
    text-anchor: middle;
    pointer-events: none;
  }
  .network-zone-name,
  .network-host text {
    fill: var(--ui-color-text);
    font: 700 var(--ui-text-sm) var(--ui-font-ui);
  }
  .network-zone-meta,
  .network-host-meta,
  .network-operational-flow text {
    fill: var(--ui-color-text-secondary);
    font: var(--ui-text-xs) var(--ui-font-mono);
  }
  .network-zone-glyph {
    cursor: pointer;
  }
  .network-zone-glyph circle {
    fill: var(--ui-color-paper);
    stroke: var(--ui-color-accent);
    stroke-width: 2;
  }
  .network-zone-glyph path {
    fill: none;
    stroke: var(--ui-color-text);
    stroke-width: 2;
  }
  .network-zone-glyph text {
    fill: var(--ui-color-text);
    font: 700 var(--ui-text-xs) var(--ui-font-mono);
    pointer-events: none;
  }
  .network-host {
    cursor: pointer;
  }
  .network-host > rect {
    fill: var(--ui-color-paper);
    stroke: var(--ui-color-accent);
    stroke-width: 1.5;
  }
  .network-host-glyph,
  .network-service-row,
  .network-vulnerability-row {
    cursor: pointer;
  }
  .network-host-glyph circle {
    fill: var(--ui-color-accent-soft);
    stroke: var(--ui-color-accent);
    stroke-width: 1.5;
  }
  .network-host-glyph path {
    fill: none;
    stroke: var(--ui-color-text);
    stroke-width: 1.5;
  }
  .network-service-row rect {
    fill: var(--ui-color-accent-soft);
    stroke: var(--ui-color-accent);
    stroke-width: 1;
  }
  .network-vulnerability-row rect {
    fill: var(--ui-color-paper);
    stroke: var(--ui-color-border);
    stroke-width: 1;
  }
  .network-service-row text,
  .network-vulnerability-row text {
    fill: var(--ui-color-text-secondary);
    font: var(--ui-text-xs) var(--ui-font-mono);
  }
  .network-operational-flow path {
    fill: none;
    stroke: var(--ui-color-node-service);
    stroke-width: 1.5;
    stroke-dasharray: 6 4;
    pointer-events: none;
  }
  .network-operational-flow text {
    pointer-events: none;
  }
  .network-controls {
    right: var(--ui-space-3);
    bottom: var(--ui-space-3);
  }
  .network-controls output {
    min-width: 3rem;
    text-align: center;
    font-family: var(--ui-font-mono);
  }
  .network-outline {
    position: absolute;
    z-index: 1;
    top: calc(var(--ui-space-3) + 5rem);
    right: var(--ui-space-3);
    max-inline-size: min(18rem, calc(100% - 2 * var(--ui-space-3)));
    padding: 0.375rem 0.5rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
    font-size: var(--ui-text-xs);
  }
  .network-outline summary {
    cursor: pointer;
    font-weight: 700;
  }
  .network-outline ul {
    margin: var(--ui-space-2) 0 0;
    padding-inline-start: var(--ui-space-4);
  }
  .network-outline button {
    margin: var(--ui-space-1);
    border: 0;
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-accent-soft);
    color: var(--ui-color-text);
    padding: 0.25rem 0.5rem;
  }
</style>
