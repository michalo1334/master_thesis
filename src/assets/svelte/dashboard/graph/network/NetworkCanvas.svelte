<script lang="ts">
  import type { DashboardApi } from "../../dashboard-api";
  import type { GraphProjectionOperationalFlow } from "../../contract";
  import type { EditableGraphDocument } from "../EditableGraphDocument.svelte";
  import {
    layoutHostCards,
    layoutZones,
    type ZonePosition,
  } from "./NetworkCanvasLayout";
  import { projectNetwork } from "./NetworkCanvasProjection";
  import {
    clampZoom,
    formatWorldTransform,
    isActivationKey,
    screenToWorld,
    ZOOM_STEP,
  } from "../canvas/canvasState";

  const COLLAPSED_RADIUS = { x: 130, y: 72 };
  const EXPANDED_RADIUS = { x: 235, y: 155 };
  const HOST_BATCH_SIZE = 6;
  const HOST_WIDTH = 128;
  const HOST_BASE_HEIGHT = 52;
  const HOST_DETAIL_TOP = 8;
  const SERVICE_ROW_HEIGHT = 24;
  const CVE_ROW_HEIGHT = 18;
  const HOST_GRID_OFFSET = 28;

  interface Props {
    document: EditableGraphDocument;
    api: DashboardApi;
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

  let { document, api }: Props = $props();
  let viewport = $state({ width: 0, height: 0 });
  let view = $state({ zoom: 100, pan: { x: 0, y: 0 } });
  let expandedSegmentId = $state<string>();
  let expandedHostId = $state<string>();
  let visibleHostCount = $state(0);
  let zonePositions = $state.raw(new Map<string, ZonePosition>());
  let panDrag = $state<{
    pointerId: number;
    x: number;
    y: number;
    pan: ZonePosition;
  }>();
  let status = $state("");
  let serverFlows = $state<readonly GraphProjectionOperationalFlow[]>();
  let projectedRevisionId = $state<string | null>(null);
  let projectionError = $state("");

  let projection = $derived(
    projectNetwork(
      document.graph,
      document.loadedRevisionId === projectedRevisionId
        ? serverFlows
        : undefined,
    ),
  );
  let zones = $derived.by<DisplayZone[]>(() =>
    projection.segments.map((segment) => {
      const expanded = segment.id === expandedSegmentId;
      return {
        ...segment,
        position: zonePositions.get(segment.id) ?? { ...segment.position },
        radius: expanded
          ? expandedRadius(visibleHosts(segment))
          : COLLAPSED_RADIUS,
      };
    }),
  );
  let zoneById = $derived(new Map(zones.map((zone) => [zone.id, zone])));
  let hostById = $derived(
    new Map(projection.hosts.map((host) => [host.id, host])),
  );
  let hostPositions = $derived.by(() => {
    const expanded = expandedSegmentId
      ? zoneById.get(expandedSegmentId)
      : undefined;
    return expanded
      ? gridHosts(expanded, visibleHosts(expanded))
      : new Map<string, ZonePosition>();
  });
  let visibleFlows = $derived(
    projection.operationalFlows.filter(
      (flow) =>
        hostPositions.has(flow.sourceId) && hostPositions.has(flow.targetId),
    ),
  );
  let selectedHost = $derived(
    document.selection?.type === "Host" ? document.selection : undefined,
  );
  let projectionStale = $derived(
    document.loadedRevisionId !== null &&
      (document.isDirty || document.loadedRevisionId !== projectedRevisionId),
  );
  let transform = $derived(formatWorldTransform(view));
  let diagramId = $props.id();

  $effect(() => {
    const revisionId = document.loadedRevisionId;
    if (!revisionId || revisionId === projectedRevisionId || document.isDirty)
      return;
    let active = true;
    void api
      .fetchGraphProjection(revisionId)
      .then((reply) => {
        if (!active || document.loadedRevisionId !== revisionId) return;
        if (reply.status === "ok") {
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

  function visibleHosts(
    zone: Pick<DisplayZone, "id" | "hosts">,
  ): DisplayZone["hosts"] {
    return zone.id === expandedSegmentId
      ? zone.hosts.slice(0, visibleHostCount)
      : [];
  }

  function serviceDetailHeight(
    service: (typeof projection.hosts)[number]["services"][number],
  ): number {
    return SERVICE_ROW_HEIGHT + service.vulnerabilities.length * CVE_ROW_HEIGHT;
  }

  function hostCardHeight(host: (typeof projection.hosts)[number]): number {
    return host.id === expandedHostId
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

  function expandedRadius(
    hosts: readonly (typeof projection.hosts)[number][],
  ): { x: number; y: number } {
    const positions = layoutHostCards(
      { x: 0, y: HOST_GRID_OFFSET },
      hosts.map((host) => ({ id: host.id, height: hostCardHeight(host) })),
    );
    let maxX = 0;
    let maxY = 0;
    for (const host of hosts) {
      const position = positions.get(host.id)!;
      maxX = Math.max(maxX, Math.abs(position.x) + HOST_WIDTH / 2);
      maxY = Math.max(maxY, Math.abs(position.y) + hostCardHeight(host) / 2);
    }
    return {
      x: Math.max(EXPANDED_RADIUS.x, (maxX + 12) * Math.SQRT2),
      y: Math.max(EXPANDED_RADIUS.y, (maxY + 12) * Math.SQRT2),
    };
  }

  function nextHostBatch(zone: DisplayZone): number {
    const shown = zone.id === expandedSegmentId ? visibleHostCount : 0;
    return Math.min(HOST_BATCH_SIZE, Math.max(0, zone.hosts.length - shown));
  }

  function gridHosts(
    zone: DisplayZone,
    hosts: readonly (typeof zone.hosts)[number][],
  ): Map<string, ZonePosition> {
    return layoutHostCards(
      { x: zone.position.x, y: zone.position.y + HOST_GRID_OFFSET },
      hosts.map((host) => ({ id: host.id, height: hostCardHeight(host) })),
    );
  }

  function runZoneLayout(nextExpandedId?: string): void {
    const next = layoutZones(
      projection.segments.map((segment) => ({
        id: segment.id,
        position:
          nextExpandedId === segment.id
            ? { ...segment.position }
            : (zonePositions.get(segment.id) ?? { ...segment.position }),
        radius:
          nextExpandedId === segment.id
            ? expandedRadius(segment.hosts.slice(0, visibleHostCount))
            : COLLAPSED_RADIUS,
        pinned: nextExpandedId === segment.id,
      })),
      projection.segmentLinks.map((link) => ({
        sourceId: link.sourceId,
        targetId: link.targetId,
      })),
    );
    zonePositions = next;
  }

  function toggleZone(segmentId: string): void {
    const nextExpandedId =
      expandedSegmentId === segmentId ? undefined : segmentId;
    const zone = projection.segments.find(
      (segment) => segment.id === nextExpandedId,
    );
    expandedSegmentId = nextExpandedId;
    expandedHostId = undefined;
    visibleHostCount = zone ? Math.min(HOST_BATCH_SIZE, zone.hosts.length) : 0;
    runZoneLayout(nextExpandedId);
  }

  function showMoreHosts(zone: DisplayZone): void {
    visibleHostCount = Math.min(
      zone.hosts.length,
      visibleHostCount + HOST_BATCH_SIZE,
    );
    runZoneLayout(zone.id);
  }

  function toggleHostDetail(hostId: string): void {
    expandedHostId = expandedHostId === hostId ? undefined : hostId;
    if (expandedSegmentId) runZoneLayout(expandedSegmentId);
  }

  function selectZone(zone: DisplayZone): void {
    if (zone.node) document.selectNode(zone.id);
    else toggleZone(zone.id);
  }

  function startPan(event: PointerEvent): void {
    const surface = event.currentTarget as SVGSVGElement;
    const zoneId = (event.target as SVGElement).dataset.zoneId;
    if (zoneId) {
      const zone = zoneById.get(zoneId);
      if (zone) selectZone(zone);
      return;
    }
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
    const reply = await api.createNodeDraft({
      node_type: type,
      x_pos: position.x,
      y_pos: position.y,
    });
    if (reply.status === "ok" && reply.node) document.addNode(reply.node);
  }

  function activateKey(event: KeyboardEvent, action: () => void): void {
    if (!isActivationKey(event.key)) return;
    event.preventDefault();
    action();
  }
</script>

<section class="network-canvas" aria-label="Network canvas">
  <div class="network-toolbar">
    <button type="button" onclick={() => addNode("Host")}>Add host</button>
    <button type="button" onclick={() => addNode("NetworkSegment")}
      >Add segment</button
    >
    {#if selectedHost}
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
    onpointermove={movePan}
    onpointerup={endPan}
    onpointercancel={endPan}
    onwheel={zoomAtCursor}
  >
    <defs>
      {#each zones as zone (zone.id)}
        <clipPath id={`${diagramId}-${zone.id}`} clipPathUnits="userSpaceOnUse">
          <ellipse
            cx={zone.position.x}
            cy={zone.position.y}
            rx={zone.radius.x}
            ry={zone.radius.y}
          />
        </clipPath>
      {/each}
    </defs>
    <g {transform}>
      {#each projection.segmentLinks as link (link.id)}
        {@const source = zoneById.get(link.sourceId)}
        {@const target = zoneById.get(link.targetId)}
        {#if source && target}
          {@const boundary = zoneBoundary(source, target)}
          <g
            class="network-policy-link"
            data-testid="policy-link"
            role="button"
            tabindex="0"
            aria-label="Segment reachability"
            onclick={() => document.selectEdge(link.edgeIds[0]!)}
            onkeydown={(event) =>
              activateKey(event, () => document.selectEdge(link.edgeIds[0]!))}
          >
            <path
              d={`M ${boundary[0].x} ${boundary[0].y} L ${boundary[1].x} ${boundary[1].y}`}
            />
          </g>
        {/if}
      {/each}

      {#each zones as zone (zone.id)}
        {@const selected =
          document.canvasSelection.kind === "node" &&
          document.canvasSelection.nodeId === zone.id}
        {@const expanded = expandedSegmentId === zone.id}
        {@const nextBatch = nextHostBatch(zone)}
        {@const glyphX = zone.position.x + zone.radius.x * 0.82}
        {@const glyphY = zone.position.y - zone.radius.y * 0.57}
        <g
          class={["network-zone", selected && "selected"]}
          data-testid="network-zone"
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
            aria-label={expanded && nextBatch
              ? `Show ${nextBatch} more hosts in ${zone.name} zone`
              : expanded
                ? `Collapse ${zone.name} zone in diagram`
                : `Show ${nextBatch} hosts in ${zone.name} zone`}
            onclick={() =>
              expanded && nextBatch ? showMoreHosts(zone) : toggleZone(zone.id)}
            onkeydown={(event) =>
              activateKey(event, () =>
                expanded && nextBatch
                  ? showMoreHosts(zone)
                  : toggleZone(zone.id),
              )}
          >
            <circle cx={glyphX} cy={glyphY} r="12" />
            <path
              d={`M ${glyphX - 5} ${glyphY} H ${glyphX + 5}${nextBatch ? ` M ${glyphX} ${glyphY - 5} V ${glyphY + 5}` : ""}`}
            />
            <text x={glyphX + 18} y={glyphY + 4}
              >{nextBatch ? `+${nextBatch}` : "−"}</text
            >
          </g>
        </g>
      {/each}

      {#if expandedSegmentId}
        {@const expandedZone = zoneById.get(expandedSegmentId)}
        {#if expandedZone}
          <g clip-path={`url(#${diagramId}-${expandedZone.id})`}>
            {#each visibleFlows as flow (flow.id)}
              {@const source = hostPositions.get(flow.sourceId)!}
              {@const target = hostPositions.get(flow.targetId)!}
              <g
                class="network-operational-flow"
                role="img"
                aria-label={`Operational flow from ${flow.sourceName} to ${flow.serviceName}`}
              >
                <path
                  d={`M ${source.x} ${source.y} L ${target.x} ${target.y}`}
                />
                <text
                  x={(source.x + target.x) / 2}
                  y={(source.y + target.y) / 2 - 6}>{flow.serviceName}</text
                >
              </g>
            {/each}
            {#each visibleHosts(expandedZone) as host (host.id)}
              {@const position = hostPositions.get(host.id)!}
              {@const height = hostCardHeight(host)}
              {@const detailExpanded = expandedHostId === host.id}
              {@const selected =
                document.canvasSelection.kind === "node" &&
                document.canvasSelection.nodeId === host.id}
              <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
              <g
                class={["network-host", selected && "selected"]}
                data-testid="host-node"
                data-host-id={host.id}
                data-card-height={height}
                transform={`translate(${position.x - HOST_WIDTH / 2} ${position.y - height / 2})`}
                onclick={() => document.selectNode(host.id)}
              >
                <rect width={HOST_WIDTH} {height} rx="7" />
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
                        document.selectNode(service.node.id);
                      }}
                      onkeydown={(event) => {
                        event.stopPropagation();
                        activateKey(event, () =>
                          document.selectNode(service.node.id),
                        );
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
                          document.selectNode(vulnerability.id);
                        }}
                        onkeydown={(event) => {
                          event.stopPropagation();
                          activateKey(event, () =>
                            document.selectNode(vulnerability.id),
                          );
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
          </g>
        {/if}
      {/if}
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
        {@const expanded = expandedSegmentId === zone.id}
        <li>
          {#if zone.node}
            <button type="button" onclick={() => document.selectNode(zone.id)}
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
              {#each visibleHosts(zone) as host (host.id)}
                <li>
                  <button
                    type="button"
                    onclick={() => document.selectNode(host.id)}
                    >Select host {host.node.data.name}</button
                  >
                  {#if host.services.length}
                    <button
                      type="button"
                      aria-expanded={expandedHostId === host.id}
                      onclick={() => toggleHostDetail(host.id)}
                      >{expandedHostId === host.id ? "Collapse" : "Expand"} details
                      for {host.node.data.name}</button
                    >
                  {/if}
                  {#if expandedHostId === host.id}
                    <ul>
                      {#each host.services as service (service.node.id)}
                        <li>
                          <button
                            type="button"
                            onclick={() => document.selectNode(service.node.id)}
                            >Select service {service.node.data.name}</button
                          >
                          {#if service.vulnerabilities.length}
                            <ul>
                              {#each service.vulnerabilities as vulnerability (vulnerability.id)}
                                <li>
                                  <button
                                    type="button"
                                    onclick={() =>
                                      document.selectNode(vulnerability.id)}
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
            {#if nextHostBatch(zone)}
              <button type="button" onclick={() => showMoreHosts(zone)}
                >Show more hosts</button
              >
            {/if}
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
    background: var(--ds-color-canvas);
  }
  .network-toolbar,
  .network-controls {
    position: absolute;
    z-index: 1;
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--ds-space-2);
    padding: 0.375rem 0.5rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-md);
    font-size: var(--ds-text-xs);
  }
  .network-toolbar {
    top: calc(var(--ds-space-3) + 2.5rem);
    left: var(--ds-space-3);
    max-inline-size: calc(100% - 2 * var(--ds-space-3));
  }
  .network-toolbar button,
  .network-controls button,
  .network-toolbar select {
    border: 0;
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-accent-soft);
    color: var(--ds-color-text);
    padding: 0.25rem 0.5rem;
  }
  .network-toolbar-status {
    color: var(--ds-color-text-secondary);
  }
  .network-projection-notice {
    position: absolute;
    z-index: 1;
    top: calc(var(--ds-space-3) + 5rem);
    left: 50%;
    transform: translateX(-50%);
    padding: 0.25rem 0.5rem;
    border: 1px solid var(--ds-color-warning);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-warning-bg);
    color: var(--ds-color-warning-text);
    font-size: var(--ds-text-xs);
    box-shadow: var(--ds-shadow-md);
  }
  .network-surface {
    display: block;
    width: 100%;
    height: 100%;
    touch-action: none;
    background-image: radial-gradient(
      var(--ds-color-border) 1px,
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
    stroke: var(--ds-color-preview-edge);
    stroke-width: 2;
  }
  .network-zone {
    cursor: pointer;
  }
  .network-zone > ellipse {
    fill: var(--ds-color-accent-soft);
    stroke: var(--ds-color-accent);
    stroke-width: 2;
  }
  .network-zone.selected > ellipse,
  .network-host.selected > rect {
    stroke: var(--ds-color-focus);
    stroke-width: 3;
  }
  .network-zone-name,
  .network-zone-meta {
    text-anchor: middle;
    pointer-events: none;
  }
  .network-zone-name,
  .network-host text {
    fill: var(--ds-color-text);
    font: 700 var(--ds-text-sm) var(--ds-font-ui);
  }
  .network-zone-meta,
  .network-host-meta,
  .network-operational-flow text {
    fill: var(--ds-color-text-secondary);
    font: var(--ds-text-xs) var(--ds-font-mono);
  }
  .network-zone-glyph {
    cursor: pointer;
  }
  .network-zone-glyph circle {
    fill: var(--ds-color-paper);
    stroke: var(--ds-color-accent);
    stroke-width: 2;
  }
  .network-zone-glyph path {
    fill: none;
    stroke: var(--ds-color-text);
    stroke-width: 2;
  }
  .network-zone-glyph text {
    fill: var(--ds-color-text);
    font: 700 var(--ds-text-xs) var(--ds-font-mono);
    pointer-events: none;
  }
  .network-host {
    cursor: pointer;
  }
  .network-host > rect {
    fill: var(--ds-color-paper);
    stroke: var(--ds-color-accent);
    stroke-width: 1.5;
  }
  .network-host-glyph,
  .network-service-row,
  .network-vulnerability-row {
    cursor: pointer;
  }
  .network-host-glyph circle {
    fill: var(--ds-color-accent-soft);
    stroke: var(--ds-color-accent);
    stroke-width: 1.5;
  }
  .network-host-glyph path {
    fill: none;
    stroke: var(--ds-color-text);
    stroke-width: 1.5;
  }
  .network-service-row rect {
    fill: var(--ds-color-accent-soft);
    stroke: var(--ds-color-accent);
    stroke-width: 1;
  }
  .network-vulnerability-row rect {
    fill: var(--ds-color-paper);
    stroke: var(--ds-color-border);
    stroke-width: 1;
  }
  .network-service-row text,
  .network-vulnerability-row text {
    fill: var(--ds-color-text-secondary);
    font: var(--ds-text-xs) var(--ds-font-mono);
  }
  .network-operational-flow path {
    fill: none;
    stroke: var(--ds-color-node-service);
    stroke-width: 1.5;
    stroke-dasharray: 6 4;
    pointer-events: none;
  }
  .network-operational-flow text {
    pointer-events: none;
  }
  .network-controls {
    right: var(--ds-space-3);
    bottom: var(--ds-space-3);
  }
  .network-controls output {
    min-width: 3rem;
    text-align: center;
    font-family: var(--ds-font-mono);
  }
  .network-outline {
    position: absolute;
    z-index: 1;
    top: calc(var(--ds-space-3) + 5rem);
    right: var(--ds-space-3);
    max-inline-size: min(18rem, calc(100% - 2 * var(--ds-space-3)));
    padding: 0.375rem 0.5rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-md);
    font-size: var(--ds-text-xs);
  }
  .network-outline summary {
    cursor: pointer;
    font-weight: 700;
  }
  .network-outline ul {
    margin: var(--ds-space-2) 0 0;
    padding-inline-start: var(--ds-space-4);
  }
  .network-outline button {
    margin: var(--ds-space-1);
    border: 0;
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-accent-soft);
    color: var(--ds-color-text);
    padding: 0.25rem 0.5rem;
  }
</style>
