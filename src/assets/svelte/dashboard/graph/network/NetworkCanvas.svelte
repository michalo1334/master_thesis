<script lang="ts">
  import { SvelteSet } from "svelte/reactivity";
  import type { DashboardApi } from "../../dashboard-api";
  import type { EditableGraphDocument } from "../EditableGraphDocument.svelte";
  import {
    cullNetworkHosts,
    cullNetworkSegments,
    projectNetwork,
  } from "./NetworkCanvasProjection";

  const MIN_ZOOM = 25;
  const MAX_ZOOM = 200;
  const ZOOM_STEP = 10;
  const HOST_WIDTH = 160;
  const HOST_HEIGHT = 78;

  interface Props {
    document: EditableGraphDocument;
    api: DashboardApi;
  }

  let { document, api }: Props = $props();
  let viewport = $state({ width: 0, height: 0 });
  let view = $state({ zoom: 100, pan: { x: 0, y: 0 } });
  let expandedHostIds = $state.raw(new SvelteSet<string>());
  let drag = $state<
    | {
        kind: "pan";
        pointerId: number;
        x: number;
        y: number;
        pan: { x: number; y: number };
      }
    | {
        kind: "host";
        pointerId: number;
        hostId: string;
        x: number;
        y: number;
        position: { x: number; y: number };
        moved: boolean;
      }
    | {
        kind: "containment";
        pointerId: number;
        segmentId: string;
        point: { x: number; y: number };
      }
  >();
  let suppressClick = $state(false);
  let status = $state("");
  let keyboardContainmentSourceId = $state<string>();

  let projection = $derived(projectNetwork(document.graph));
  let visibleHosts = $derived(
    cullNetworkHosts(
      projection.hosts,
      viewport,
      view.pan,
      view.zoom,
      180,
      hostHeight,
    ),
  );
  let visibleSegments = $derived(
    cullNetworkSegments(projection.segments, viewport, view.pan, view.zoom),
  );
  let visibleSegmentIds = $derived(
    new Set(visibleSegments.map((segment) => segment.id)),
  );
  let segmentById = $derived(
    new Map(projection.segments.map((segment) => [segment.id, segment])),
  );
  let selectedHost = $derived(
    document.selection?.type === "Host" ? document.selection : undefined,
  );
  let showHosts = $derived(view.zoom >= 60);
  let containmentDrag = $derived(
    drag?.kind === "containment" ? drag : undefined,
  );
  let transform = $derived(
    `translate(${view.pan.x} ${view.pan.y}) scale(${view.zoom / 100})`,
  );

  function clampZoom(value: number): number {
    return Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, value));
  }

  function graphPoint(event: PointerEvent | MouseEvent): {
    x: number;
    y: number;
  } {
    const bounds = (event.currentTarget as Element)
      .closest<SVGSVGElement>("svg.network-surface")
      ?.getBoundingClientRect();
    if (!bounds) return { x: 0, y: 0 };
    const scale = view.zoom / 100;
    return {
      x: (event.clientX - bounds.left - view.pan.x) / scale,
      y: (event.clientY - bounds.top - view.pan.y) / scale,
    };
  }

  function hostAt(point: { x: number; y: number }): string | undefined {
    return projection.hosts.find((host) => {
      const { node } = host;
      const { x_pos, y_pos } = node.view_data;
      return (
        point.x >= x_pos &&
        point.x <= x_pos + HOST_WIDTH &&
        point.y >= y_pos &&
        point.y <= y_pos + hostHeight(host)
      );
    })?.id;
  }

  function captureSurface(event: PointerEvent): void {
    (event.currentTarget as Element)
      .closest<SVGSVGElement>("svg.network-surface")
      ?.setPointerCapture(event.pointerId);
  }

  function startPan(event: PointerEvent): void {
    if (event.button !== 0 || !event.isPrimary) return;
    const surface = event.currentTarget as SVGSVGElement;
    surface.setPointerCapture(event.pointerId);
    drag = {
      kind: "pan",
      pointerId: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      pan: { ...view.pan },
    };
  }

  function startHostDrag(hostId: string, event: PointerEvent): void {
    if (event.button !== 0 || !event.isPrimary) return;
    event.stopPropagation();
    const host = projection.hosts.find((item) => item.id === hostId);
    if (!host) return;
    captureSurface(event);
    drag = {
      kind: "host",
      pointerId: event.pointerId,
      hostId,
      x: event.clientX,
      y: event.clientY,
      position: { x: host.node.view_data.x_pos, y: host.node.view_data.y_pos },
      moved: false,
    };
  }

  function startContainment(segmentId: string, event: PointerEvent): void {
    if (event.button !== 0 || !event.isPrimary) return;
    event.stopPropagation();
    captureSurface(event);
    drag = {
      kind: "containment",
      pointerId: event.pointerId,
      segmentId,
      point: graphPoint(event),
    };
  }

  function move(event: PointerEvent): void {
    const activeDrag = drag;
    if (!activeDrag || activeDrag.pointerId !== event.pointerId) return;
    if (activeDrag.kind === "pan") {
      view.pan = {
        x: activeDrag.pan.x + event.clientX - activeDrag.x,
        y: activeDrag.pan.y + event.clientY - activeDrag.y,
      };
      return;
    }
    if (activeDrag.kind === "containment") {
      activeDrag.point = graphPoint(event);
      return;
    }
    const scale = view.zoom / 100;
    const deltaX = event.clientX - activeDrag.x;
    const deltaY = event.clientY - activeDrag.y;
    if (Math.hypot(deltaX, deltaY) > 3) {
      activeDrag.moved = true;
      suppressClick = true;
    }
    document.graph = {
      ...document.graph,
      nodes: document.graph.nodes.map((node) =>
        node.id === activeDrag.hostId
          ? {
              ...node,
              view_data: {
                ...node.view_data,
                x_pos: activeDrag.position.x + deltaX / scale,
                y_pos: activeDrag.position.y + deltaY / scale,
              },
            }
          : node,
      ),
    };
  }

  async function createContainment(
    segmentId: string,
    hostId: string,
  ): Promise<void> {
    const host = projection.hosts.find((item) => item.id === hostId);
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
    const segmentId = (event.currentTarget as HTMLSelectElement).value;
    (event.currentTarget as HTMLSelectElement).value = "";
    if (segmentId && selectedHost)
      void createContainment(segmentId, selectedHost.id);
  }

  function end(event: PointerEvent, commit: boolean): void {
    if (!drag || drag.pointerId !== event.pointerId) return;
    const current = drag;
    const target = event.currentTarget as Element;
    const point = graphPoint(event);
    drag = undefined;
    if (target.hasPointerCapture(event.pointerId))
      target.releasePointerCapture(event.pointerId);
    if (!commit) return;
    if (current.kind === "host" && !current.moved) {
      suppressClick = false;
      document.selectNode(current.hostId);
    }
    const targetId = hostAt(point);
    if (current.kind === "containment" && targetId)
      void createContainment(current.segmentId, targetId);
  }

  function selectHost(hostId: string): void {
    if (suppressClick) {
      suppressClick = false;
      return;
    }
    document.selectNode(hostId);
  }

  function activateKey(event: KeyboardEvent, action: () => void): void {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    action();
  }

  function activateHost(hostId: string): void {
    const host = projection.hosts.find((item) => item.id === hostId);
    if (!host) return;
    if (keyboardContainmentSourceId) {
      const segmentId = keyboardContainmentSourceId;
      keyboardContainmentSourceId = undefined;
      status = "";
      void createContainment(segmentId, host.id);
      return;
    }
    selectHost(hostId);
  }

  function startKeyboardContainment(segmentId: string): void {
    keyboardContainmentSourceId = segmentId;
    status = "Select an unassigned host and press Enter.";
  }

  function toggleHost(hostId: string): void {
    expandedHostIds = new SvelteSet(expandedHostIds);
    expandedHostIds.has(hostId)
      ? expandedHostIds.delete(hostId)
      : expandedHostIds.add(hostId);
  }

  async function addNode(type: "Host" | "NetworkSegment"): Promise<void> {
    const scale = view.zoom / 100;
    const reply = await api.createNodeDraft({
      node_type: type,
      x_pos: viewport.width / 2 / scale - view.pan.x / scale,
      y_pos: viewport.height / 2 / scale - view.pan.y / scale,
    });
    if (reply.status === "ok" && reply.node) document.addNode(reply.node);
  }

  function detailRows(host: (typeof projection.hosts)[number]): number {
    return host.services.reduce(
      (rows, service) => rows + 1 + service.vulnerabilities.length,
      0,
    );
  }

  function vulnerabilityCount(host: (typeof projection.hosts)[number]): number {
    return host.services.reduce(
      (count, service) => count + service.vulnerabilities.length,
      0,
    );
  }

  function hostSummary(host: (typeof projection.hosts)[number]): string {
    return `${host.services.length} svc / ${vulnerabilityCount(host)} CVEs`;
  }

  function hostHeight(host: (typeof projection.hosts)[number]): number {
    return (
      HOST_HEIGHT + (expandedHostIds.has(host.id) ? detailRows(host) * 22 : 0)
    );
  }

  function serviceOffset(
    host: (typeof projection.hosts)[number],
    index: number,
  ): number {
    return host.services
      .slice(0, index)
      .reduce((rows, service) => rows + 1 + service.vulnerabilities.length, 0);
  }

  function zoomBy(delta: number): void {
    view.zoom = clampZoom(view.zoom + delta);
  }
</script>

<section class="network-canvas" aria-label="Compact network canvas">
  <div class="network-toolbar">
    <div class="network-toolbar-actions">
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
      <span class="network-toolbar-count">
        <span class="network-toolbar-host-count"
          >{projection.hosts.length} hosts ·
        </span>{showHosts ? visibleHosts.length : visibleSegments.length} visible
      </span>
      <span class="network-toolbar-segment-count"
        >{projection.segments.length} segments</span
      >
    </div>
    {#if status}
      <div class="network-toolbar-status" role="status" aria-live="polite">
        {status}
      </div>
    {/if}
  </div>
  {#if showHosts && projection.segments.length > 0}
    <section class="network-segment-indicator" aria-label="Network segments">
      <span>Segments</span>
      <ul>
        {#each projection.segments as segment (segment.id)}
          {@const selected =
            document.canvasSelection.kind === "node" &&
            document.canvasSelection.nodeId === segment.id}
          <li>
            {#if segment.node}
              <button
                type="button"
                aria-pressed={selected}
                aria-label={`Select network segment ${segment.name}, ${segment.hosts.length} hosts`}
                onclick={() => document.selectNode(segment.id)}
                >{segment.name}<span aria-hidden="true"
                  >{segment.hosts.length}</span
                ></button
              >
            {:else}
              <span>{segment.name} ({segment.hosts.length} hosts)</span>
            {/if}
          </li>
        {/each}
      </ul>
    </section>
  {/if}
  <svg
    class="network-surface"
    role="group"
    viewBox={`0 0 ${viewport.width} ${viewport.height}`}
    aria-label="Network topology. Drag blank space to pan, drag a host to move it, and drag a segment connector to assign a host."
    bind:clientWidth={viewport.width}
    bind:clientHeight={viewport.height}
    onpointerdown={startPan}
    onpointermove={move}
    onpointerup={(event) => end(event, true)}
    onpointercancel={(event) => end(event, false)}
    onlostpointercapture={(event) => {
      if (drag?.pointerId === event.pointerId) drag = undefined;
    }}
    onwheel={(event) => {
      event.preventDefault();
      zoomBy(event.deltaY < 0 ? ZOOM_STEP : -ZOOM_STEP);
    }}
  >
    <g {transform}>
      {#if !showHosts}
        {#each projection.segmentLinks as link (link.id)}
          {#if visibleSegmentIds.has(link.sourceId) && visibleSegmentIds.has(link.targetId)}
            {@const source = segmentById.get(link.sourceId)!}
            {@const target = segmentById.get(link.targetId)!}
            <g
              class="network-link"
              role="button"
              tabindex="0"
              aria-label="Segment reachability"
              onclick={() => document.selectEdge(link.edgeIds[0])}
              onkeydown={(event) =>
                activateKey(event, () => document.selectEdge(link.edgeIds[0]))}
            >
              <path
                d={`M ${source.position.x + 180} ${source.position.y + 40} L ${target.position.x} ${target.position.y + 40}`}
              />
              {#if link.edgeIds.length > 1}
                <text
                  x={(source.position.x + target.position.x + 180) / 2}
                  y={(source.position.y + target.position.y + 80) / 2}
                  >{link.edgeIds.length}</text
                >
              {/if}
            </g>
          {/if}
        {/each}
      {/if}
      {#if containmentDrag}
        {@const source = segmentById.get(containmentDrag.segmentId)}
        {#if source}
          <path
            class="network-preview"
            d={`M ${source.position.x + 180} ${source.position.y + 40} L ${containmentDrag.point.x} ${containmentDrag.point.y}`}
          />
        {/if}
      {/if}
      {#if showHosts}
        {#each visibleHosts as host (host.id)}
          {@const isExpanded = expandedHostIds.has(host.id)}
          {@const selected =
            document.canvasSelection.kind === "node" &&
            document.canvasSelection.nodeId === host.id}
          <g
            class={["network-host", selected && "selected"]}
            transform={`translate(${host.node.view_data.x_pos} ${host.node.view_data.y_pos})`}
            onpointerdown={(event) => startHostDrag(host.id, event)}
            onclick={() => selectHost(host.id)}
            role="button"
            tabindex="0"
            aria-pressed={selected}
            aria-label={`Host ${host.node.data.name}`}
            onkeydown={(event) =>
              activateKey(event, () => activateHost(host.id))}
          >
            <rect
              width={HOST_WIDTH}
              height={HOST_HEIGHT + (isExpanded ? detailRows(host) * 22 : 0)}
              rx="8"
            />
            <text class="network-host-name" x="12" y="24"
              >{host.node.data.name}</text
            >
            <text class="network-host-meta" x="12" y="46"
              >{hostSummary(host)}</text
            >
            <text class="network-host-meta" x="12" y="64"
              >{segmentById.get(host.segmentId)?.name ?? "Unassigned"}</text
            >
            {#if host.services.length > 0}
              <g
                class="network-expand"
                role="button"
                tabindex="0"
                aria-label={`${isExpanded ? "Collapse" : "Expand"} ${host.node.data.name}`}
                onpointerdown={(event) => event.stopPropagation()}
                onclick={(event) => {
                  event.stopPropagation();
                  toggleHost(host.id);
                }}
                onkeydown={(event) => {
                  event.stopPropagation();
                  activateKey(event, () => toggleHost(host.id));
                }}
              >
                <text x="142" y="24">{isExpanded ? "-" : "+"}</text>
              </g>
            {/if}
            {#if isExpanded}
              {#each host.services as service, index (service.node.id)}
                {@const offset = serviceOffset(host, index)}
                <g
                  class="network-child"
                  transform={`translate(12 ${HOST_HEIGHT + 16 + offset * 22})`}
                  role="button"
                  tabindex="0"
                  aria-label={`Select service ${service.node.data.name}`}
                  onpointerdown={(event) => event.stopPropagation()}
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
                    class="network-child-hitbox"
                    width="144"
                    height="22"
                    y="-16"
                  />
                  <text
                    >{service.node.data.name}:{service.node.data.port} ({service
                      .vulnerabilities.length} vulnerabilities)</text
                  >
                </g>
                {#each service.vulnerabilities as vulnerability, vulnerabilityIndex (vulnerability.id)}
                  <g
                    class="network-child network-vulnerability"
                    transform={`translate(22 ${HOST_HEIGHT + 16 + (offset + vulnerabilityIndex + 1) * 22})`}
                    role="button"
                    tabindex="0"
                    aria-label={`Select vulnerability ${vulnerability.data.identifier}`}
                    onpointerdown={(event) => event.stopPropagation()}
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
                      class="network-child-hitbox"
                      width="134"
                      height="22"
                      y="-16"
                    />
                    <text
                      >{vulnerability.data.identifier} ({Math.round(
                        vulnerability.data.exploit_probability * 100,
                      )}%)</text
                    >
                  </g>
                {/each}
              {/each}
            {/if}
          </g>
        {/each}
      {:else}
        {#each visibleSegments as segment (segment.id)}
          {@const selected =
            document.canvasSelection.kind === "node" &&
            document.canvasSelection.nodeId === segment.id}
          <g
            class={["network-segment", selected && "selected"]}
            transform={`translate(${segment.position.x} ${segment.position.y})`}
            role="button"
            tabindex="0"
            aria-pressed={selected}
            aria-label={`Network segment ${segment.name}`}
            onclick={() => segment.node && document.selectNode(segment.id)}
            onkeydown={(event) =>
              activateKey(
                event,
                () => segment.node && document.selectNode(segment.id),
              )}
          >
            <rect width="180" height="80" rx="10" />
            <text class="network-host-name" x="12" y="27">{segment.name}</text>
            <text class="network-host-meta" x="12" y="50"
              >{segment.hosts.length} hosts</text
            >
            {#if segment.cidr}<text class="network-host-meta" x="12" y="68"
                >{segment.cidr}</text
              >{/if}
            {#if segment.node}
              <circle
                class="network-connector"
                cx="180"
                cy="40"
                r="6"
                role="button"
                tabindex="0"
                aria-label={`Assign host to ${segment.name}`}
                onpointerdown={(event) => startContainment(segment.id, event)}
                onclick={(event) => event.stopPropagation()}
                onkeydown={(event) => {
                  event.stopPropagation();
                  activateKey(event, () =>
                    startKeyboardContainment(segment.id),
                  );
                }}
              />
            {/if}
          </g>
        {/each}
      {/if}
    </g>
  </svg>
  <div class="network-controls" aria-label="Network canvas zoom controls">
    <button
      type="button"
      aria-label="Zoom out"
      onclick={() => zoomBy(-ZOOM_STEP)}>-</button
    >
    <output>{view.zoom}%</output>
    <button type="button" aria-label="Zoom in" onclick={() => zoomBy(ZOOM_STEP)}
      >+</button
    >
  </div>
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
    display: block;
    inline-size: fit-content;
    max-inline-size: calc(100% - 2 * var(--ds-space-3));
  }
  .network-toolbar-actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--ds-space-2);
    min-width: 0;
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
  .network-toolbar select {
    min-width: 0;
    max-inline-size: min(14rem, 100%);
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .network-toolbar-count {
    white-space: nowrap;
    font-variant-numeric: tabular-nums;
  }
  .network-toolbar-segment-count {
    display: none;
    color: var(--ds-color-text-secondary);
    white-space: nowrap;
  }
  .network-toolbar-status {
    margin-top: var(--ds-space-2);
    color: var(--ds-color-text-secondary);
  }
  .network-segment-indicator {
    position: absolute;
    z-index: 1;
    bottom: calc(var(--ds-space-3) + 3.5rem);
    right: var(--ds-space-3);
    max-inline-size: min(12rem, calc(100% - 2 * var(--ds-space-3)));
    padding: 0.375rem 0.5rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-md);
    font-size: var(--ds-text-xs);
  }
  .network-segment-indicator > span {
    color: var(--ds-color-text-secondary);
    font-weight: 700;
  }
  .network-segment-indicator ul {
    display: flex;
    flex-wrap: wrap;
    gap: 0.25rem;
    margin: 0.25rem 0 0;
    padding: 0;
    list-style: none;
  }
  .network-segment-indicator button,
  .network-segment-indicator li > span {
    display: flex;
    gap: 0.25rem;
    max-inline-size: 100%;
    padding: 0.125rem 0.25rem;
    border: 0;
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-accent-soft);
    color: var(--ds-color-text);
    font: inherit;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .network-segment-indicator button[aria-pressed="true"] {
    outline: 2px solid var(--ds-color-focus);
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
  .network-link path,
  .network-preview {
    fill: none;
    stroke: var(--ds-color-preview-edge);
    stroke-width: 2;
  }
  .network-link {
    cursor: pointer;
  }
  .network-link text {
    fill: var(--ds-color-text-secondary);
    font: var(--ds-text-xs) var(--ds-font-mono);
  }
  .network-preview {
    stroke-dasharray: 6 4;
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
  .network-host.selected > rect,
  .network-segment.selected > rect {
    stroke: var(--ds-color-focus);
    stroke-width: 3;
  }
  .network-segment rect {
    fill: var(--ds-color-accent-soft);
    stroke: var(--ds-color-accent);
    stroke-width: 2;
  }
  .network-host-name {
    fill: var(--ds-color-text);
    font: 700 var(--ds-text-sm) var(--ds-font-ui);
    pointer-events: none;
  }
  .network-host-meta,
  .network-child text {
    fill: var(--ds-color-text-secondary);
    font: var(--ds-text-xs) var(--ds-font-mono);
    pointer-events: none;
  }
  .network-connector {
    fill: var(--ds-color-paper);
    stroke: var(--ds-color-accent);
    stroke-width: 2;
    cursor: crosshair;
  }
  .network-expand {
    fill: var(--ds-color-text);
    font: 700 1.25rem var(--ds-font-ui);
  }
  .network-child {
    cursor: pointer;
  }
  .network-child-hitbox {
    fill: transparent;
    pointer-events: all;
  }
  .network-vulnerability text {
    fill: var(--ds-color-danger);
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
  @media (max-width: 35rem) {
    .network-toolbar {
      top: calc(var(--ds-space-2) + 2.5rem);
      left: var(--ds-space-2);
      max-inline-size: calc(100% - 2 * var(--ds-space-2));
    }
    .network-segment-indicator {
      display: none;
    }
    .network-toolbar-host-count {
      display: none;
    }
    .network-toolbar-segment-count {
      display: inline;
    }
  }
</style>
