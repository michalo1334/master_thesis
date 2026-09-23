<script lang="ts">
  import type {
    GraphContract,
    MissionCapabilityNode,
  } from "../../../contracts.generated/graph";
  import type { GraphProjectionOperationalFlow } from "../../../contracts.generated/dashboard/graph";
  import { onMount } from "svelte";
  import type { FilterableTableColumn } from "../../../ui-kit/composites/FilterableTable.types";
  import OptionPickerDialog from "../../../ui-kit/composites/OptionPickerDialog.svelte";
  import type { DashboardApi } from "../../dashboard-api";
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
    api: DashboardApi;
    revisionId?: string | null;
    canEditFlows: boolean;
    errors?: readonly string[];
    onUpdate: (selectable: MissionCapabilityNode) => void;
  }

  let {
    selectable,
    graph,
    api,
    revisionId = null,
    canEditFlows,
    errors = [],
    onUpdate,
  }: Props = $props();
  let pickerOpen = $state(false);
  let flows = $state<readonly GraphProjectionOperationalFlow[]>([]);
  let status = $state("");
  let flowOptions = $derived(optionsFor(graph, flows));
  let selectedFlowIds = $derived(requiredFlows(selectable.data).map(flowKey));
  let selectedFlows = $derived(flowSummariesFor(graph, selectable.data));
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

  onMount(() => {
    if (!revisionId || !canEditFlows) return;
    let active = true;
    status = "Loading reachable flows…";
    void api
      .fetchGraphProjection(revisionId)
      .then((reply) => {
        if (!active) return;
        if (reply.status === "ok") {
          flows = reply.operational_flows;
          status = "";
        } else status = "Reachable flows are unavailable.";
      })
      .catch(() => {
        if (active) status = "Reachable flows are unavailable.";
      });
    return () => {
      active = false;
    };
  });

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

  function optionsFor(
    graph: GraphContract,
    flows: readonly GraphProjectionOperationalFlow[],
  ): RequiredFlowOption[] {
    const nodes = new Map(graph.nodes.map((node) => [node.id, node]));
    return flows
      .flatMap((flow) => {
        const sourceSegmentId = graph.edges.find(
          (edge) =>
            edge.type === "Contains" &&
            edge.to_id === flow.from_id &&
            nodes.get(edge.from_id)?.type === "NetworkSegment",
        )?.from_id;
        const source = sourceSegmentId ? nodes.get(sourceSegmentId) : undefined;
        const target = nodes.get(flow.to_id);
        if (source?.type !== "NetworkSegment" || target?.type !== "Service")
          return [];
        return [
          {
            source_segment_id: source.id,
            target_service_id: target.id,
            id: `${source.id}:${target.id}`,
            source: source.data.name,
            target: `${target.data.name}:${target.data.port}`,
          },
        ];
      })
      .filter(
        (option, index, options) =>
          options.findIndex((candidate) => candidate.id === option.id) ===
          index,
      );
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
    if (!canEditFlows) {
      status = "Save the graph before selecting required flows.";
      return;
    }
    pickerOpen = true;
  }

  function updateRequiredFlows(selected: RequiredFlowOption[]): boolean {
    onUpdate({
      ...selectable,
      data: {
        ...selectable.data,
        required_flows: selected.map(
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
  {#if status}<p class="required-flows-status" role="status">{status}</p>{/if}
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
  {status}
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
