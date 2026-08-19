<script lang="ts">
  import { onMount } from "svelte";
  import type {
    GraphProjectionOperationalFlow,
    LoadedGraph,
    MissionCapabilityNode,
  } from "../../contract";
  import type { DashboardApi } from "../../dashboard-api";
  import type { FilterableTableColumn } from "../../../ui-kit/composites/FilterableTable.types";
  import Inspector from "../Inspector.svelte";
  import InspectorField from "../InspectorField.svelte";
  import OptionPickerDialog from "../../../ui-kit/composites/OptionPickerDialog.svelte";
  import { requiredFlows, type RequiredFlow } from "./mission-feasibility";

  interface RequiredFlowOption extends RequiredFlow {
    id: string;
    source: string;
    target: string;
  }

  interface Props {
    selectable: MissionCapabilityNode;
    graph: LoadedGraph;
    api: DashboardApi;
    revisionId?: string | null;
    canEditFlows: boolean;
    onUpdate: (selectable: MissionCapabilityNode) => void;
  }

  let {
    selectable,
    graph,
    api,
    revisionId = null,
    canEditFlows,
    onUpdate,
  }: Props = $props();
  let pickerOpen = $state(false);
  let flows = $state<readonly GraphProjectionOperationalFlow[]>([]);
  let status = $state("");
  let flowOptions = $derived(optionsFor(graph, flows));
  let selectedFlowIds = $derived(requiredFlows(selectable.data).map(flowKey));
  let selectedFlows = $derived(flowSummariesFor(graph, selectable.data));
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
        } else {
          status = "Reachable flows are unavailable.";
        }
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

  function optionsFor(
    graph: LoadedGraph,
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

  function openPicker(): void {
    if (!canEditFlows) {
      status = "Save the graph before selecting required flows.";
      return;
    }
    pickerOpen = true;
  }

  function flowSummariesFor(
    graph: LoadedGraph,
    data: unknown,
  ): RequiredFlowOption[] {
    const nodes = new Map(graph.nodes.map((node) => [node.id, node]));
    return requiredFlows(data).map((flow) => {
      const source = nodes.get(flow.source_segment_id);
      const target = nodes.get(flow.target_service_id);
      return {
        ...flow,
        id: flowKey(flow),
        source:
          source?.type === "NetworkSegment"
            ? source.data.name
            : flow.source_segment_id,
        target:
          target?.type === "Service"
            ? `${target.data.name}:${target.data.port}`
            : flow.target_service_id,
      };
    });
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

<Inspector title="Mission capability">
  <InspectorField
    fields={[
      { label: "Name", value: selectable.data.name },
      { label: "Description", value: selectable.data.description ?? "—" },
      { label: "Impact weight", value: String(selectable.data.impact_weight) },
      {
        label: "Minimum operational support",
        value: String(selectable.data.min_operational_support),
      },
    ]}
  />
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
    <button type="button" disabled={!canEditFlows} onclick={openPicker}
      >Change required flows</button
    >
    {#if status}
      <p class="required-flows-status" role="status">{status}</p>
    {/if}
  </section>
</Inspector>

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
    gap: var(--ds-space-2);
    margin-top: var(--ds-space-4);
    padding-top: var(--ds-space-3);
    border-top: 1px solid var(--ds-color-border-soft);
  }
  .required-flows h3,
  .required-flows p {
    margin: 0;
  }
  .required-flows h3 {
    font-size: var(--ds-text-sm);
  }
  .required-flows p {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
  }
  .required-flows ul {
    display: grid;
    gap: var(--ds-space-1);
    margin: 0;
    padding-left: 1.25rem;
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
  }
  .required-flows button {
    width: fit-content;
    min-height: var(--ds-control-height);
    padding: 0.375rem 0.5rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-surface);
  }
  .required-flows-status {
    color: var(--ds-color-warning-text) !important;
  }
</style>
