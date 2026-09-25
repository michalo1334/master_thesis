<script lang="ts">
  import type {
    GraphContract,
    MissionCapabilityNode,
  } from "../../../contracts.generated/graph";
  import type { TopologyProjection } from "../../../contracts.generated/dashboard/graph";
  import type { FilterableTableColumn } from "../../../ui-kit/composites/FilterableTable.types";
  import OptionPickerDialog from "../../../ui-kit/composites/OptionPickerDialog.svelte";
  import type { SelectionProjectionSource } from "../graph/selection-topology";
  import ErrorMessages from "../ErrorMessages.svelte";
  import { requiredFlows, type RequiredFlow } from "./mission-feasibility";

  interface RequiredFlowOption extends RequiredFlow {
    id: string;
    source: string;
    target: string;
  }

  interface Props {
    selectable: MissionCapabilityNode;
    graph: GraphContract;
    /** Accepted projection of the active graph document. */
    projection?: TopologyProjection;
    projectionSource?: SelectionProjectionSource;
    canEditFlows: boolean;
    errors?: readonly string[];
    onUpdate: (selectable: MissionCapabilityNode) => void;
  }

  let {
    selectable,
    graph,
    projection = undefined,
    projectionSource = "revision",
    canEditFlows,
    errors = [],
    onUpdate,
  }: Props = $props();
  let pickerOpen = $state(false);
  let flowOptions = $derived(optionsFor(graph, projection));
  let optionIds = $derived(new Set(flowOptions.map((flow) => flow.id)));
  let selectedFlowIds = $derived(requiredFlows(selectable.data).map(flowKey));
  let selectedFlows = $derived(flowSummariesFor(graph, selectable.data));
  /**
   * Selected flows that the accepted projection does not offer.
   *
   * The projection is the only reachability source. An absent or partial option
   * set cannot prove these flows unreachable, so they stay selected instead of
   * being cleared on confirm.
   */
  let unofferedFlows = $derived(
    selectedFlows.filter((flow) => !optionIds.has(flow.id)),
  );
  /**
   * Reachability status of the offered options.
   *
   * Options come from the accepted projection, which can be a draft of unsaved
   * edits. A missing projection leaves reachability unknown rather than
   * claiming the flows are unreachable.
   */
  let reachabilityStatus = $derived(
    !projection
      ? "Reachable flows are unknown without an accepted projection."
      : projectionSource === "draft" && projection.flow_groups.length > 0
        ? "Draft reachability · Save before simulation"
        : "",
  );
  let pickerStatus = $derived(
    [
      reachabilityStatus,
      unofferedFlows.length > 0
        ? `${unofferedFlows.length} selected ${unofferedFlows.length === 1 ? "flow is" : "flows are"} not currently reachable and stay selected.`
        : "",
    ]
      .filter(Boolean)
      .join(" "),
  );
  const fieldId = $props.id();
  const errorsId = `${fieldId}-errors`;
  const columns: readonly FilterableTableColumn<RequiredFlowOption>[] = [
    {
      key: "source",
      header: "Source segment",
      getValue: (flow) => flow.source,
    },
    {
      key: "target",
      header: "Target service",
      getValue: (flow) => flow.target,
    },
  ];

  function flowKey(flow: RequiredFlow): string {
    return `${flow.source_segment_id}:${flow.target_service_id}`;
  }

  function sourceLabel(
    node: GraphContract["nodes"][number] | undefined,
    fallback: string,
  ): string {
    if (node?.type !== "NetworkSegment") return fallback;
    return node.data.name;
  }

  function targetLabel(
    node: GraphContract["nodes"][number] | undefined,
    fallback: string,
  ): string {
    if (node?.type !== "Service") return fallback;
    return `${node.data.name}:${node.data.port}`;
  }

  /**
   * Reachable segment-to-service pairs of the accepted projection.
   *
   * The source segment comes from the projected membership of the group's
   * source host. The target services come from the group's `service_ids`. Both
   * sides resolve to names through the graph contract.
   */
  function optionsFor(
    graph: GraphContract,
    projection: TopologyProjection | undefined,
  ): RequiredFlowOption[] {
    if (!projection) return [];
    const nodes = new Map(graph.nodes.map((node) => [node.id, node]));
    const segmentByHost = new Map(
      projection.hosts.map((host) => [host.id, host.segment_id]),
    );
    const options: RequiredFlowOption[] = [];
    const seen = new Set<string>();
    for (const group of projection.flow_groups) {
      const segmentId = segmentByHost.get(group.source_host_id);
      const segment = segmentId ? nodes.get(segmentId) : undefined;
      if (segment?.type !== "NetworkSegment") continue;
      for (const serviceId of group.service_ids) {
        const service = nodes.get(serviceId);
        if (service?.type !== "Service") continue;
        const id = `${segment.id}:${service.id}`;
        if (seen.has(id)) continue;
        seen.add(id);
        options.push({
          source_segment_id: segment.id,
          target_service_id: service.id,
          id,
          source: segment.data.name,
          target: `${service.data.name}:${service.data.port}`,
        });
      }
    }
    return options;
  }

  function flowSummariesFor(
    graph: GraphContract,
    data: unknown,
  ): RequiredFlowOption[] {
    const nodes = new Map(graph.nodes.map((node) => [node.id, node]));
    return requiredFlows(data).map((flow) => {
      const source = nodes.get(flow.source_segment_id);
      const target = nodes.get(flow.target_service_id);
      return {
        ...flow,
        id: flowKey(flow),
        source: sourceLabel(source, flow.source_segment_id),
        target: targetLabel(target, flow.target_service_id),
      };
    });
  }

  function openPicker(): void {
    pickerOpen = true;
  }

  /**
   * Confirm the offered selection and keep every flow the projection does not
   * offer. Without this merge an empty or partial option set would clear
   * authored mission required flows.
   */
  function updateRequiredFlows(selected: RequiredFlowOption[]): boolean {
    onUpdate({
      ...selectable,
      data: {
        ...selectable.data,
        required_flows: [...selected, ...unofferedFlows].map(
          ({ source_segment_id, target_service_id }) => ({
            source_segment_id,
            target_service_id,
          }),
        ),
      },
    });
    return true;
  }
</script>

<section class="required-flows" aria-labelledby="required-flows-title">
  <h3 id="required-flows-title">Required flows</h3>
  {#if selectedFlows.length}
    <p>{selectedFlows.length} selected</p>
    <ul aria-label="Selected required flows">
      {#each selectedFlows as flow (flow.id)}
        <li>{flow.source} to {flow.target}</li>
      {/each}
    </ul>
  {:else}
    <p>No required flows selected.</p>
  {/if}
  <button
    type="button"
    disabled={!canEditFlows}
    aria-describedby={errors.length ? errorsId : undefined}
    onclick={openPicker}>Change required flows</button
  >
  <ErrorMessages {errors} id={errorsId} />
  {#if reachabilityStatus}
    <p class="required-flows-status" role="status">{reachabilityStatus}</p>
  {/if}
</section>

<OptionPickerDialog
  open={pickerOpen}
  onOpenChange={(open) => (pickerOpen = open)}
  items={flowOptions}
  title="Required flows"
  description="Select reachable segment-to-service flows required by this capability."
  getKey={(flow) => flow.id}
  {columns}
  mode="multiple"
  initialSelection={selectedFlowIds}
  minSelections={0}
  emptyMessage="No reachable segment-to-service flows are available."
  status={pickerStatus}
  onConfirm={updateRequiredFlows}
/>

<style>
  .required-flows {
    display: grid;
    gap: var(--ui-space-2);
    margin-top: var(--ui-space-4);
    padding-top: var(--ui-space-3);
    border-top: 1px solid var(--ui-color-border-soft);
  }
  .required-flows h3,
  .required-flows p {
    margin: 0;
  }
  .required-flows h3 {
    font-size: var(--ui-text-sm);
  }
  .required-flows p,
  .required-flows ul {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }
  .required-flows ul {
    display: grid;
    gap: var(--ui-space-1);
    margin: 0;
    padding-left: 1.25rem;
  }
  .required-flows button {
    width: fit-content;
    min-height: var(--ui-control-height);
    padding: 0.375rem 0.5rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-surface);
  }
  .required-flows-status {
    color: var(--ui-color-warning-text) !important;
  }
</style>
