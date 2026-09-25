<script lang="ts">
  import {
    edgeDataContracts,
    nodeDataContracts,
    type Edge,
    type Node,
  } from "../../../contracts.generated/graph";
  import {
    contractMetadata,
    type ContractMetadata,
    type FieldMetadata,
  } from "../../../contracts.generated/graph/data";
  import type {
    GraphContract,
    MissionCapabilityNode,
  } from "../../../contracts.generated/graph";
  import type { GraphValidationError } from "../../../contracts.generated/dashboard/graph";
  import type { TopologyProjection } from "../../../contracts.generated/dashboard/graph";
  import Inspector from "../../../ui-kit/layout/Inspector.svelte";
  import SelectionScalarField from "./SelectionScalarField.svelte";
  import RequiredFlowsField from "../mission-capabilities/RequiredFlowsField.svelte";
  import { fieldPresentation } from "./selection-inspector-presentation";
  import {
    selectionTopology,
    type SelectionProjectionSource,
  } from "./selection-topology";
  import { pathStartsWith, pathsEqual } from "./validation-path";

  interface Field {
    path: string[];
    metadata: FieldMetadata;
    value: unknown;
  }

  interface Props {
    selectable: Node | Edge;
    graph: GraphContract;
    canEditFlows: boolean;
    errors?: readonly GraphValidationError[];
    projection?: TopologyProjection;
    pendingEntityIds?: readonly string[];
    projectionStatus?: "ready" | "pending" | "error";
    projectionSource?: SelectionProjectionSource;
    pinned?: boolean;
    onTogglePin?: (entityId: string) => void;
    onUpdate: (selectable: Node | Edge) => void;
  }

  let {
    selectable,
    graph,
    canEditFlows,
    errors = [],
    projection = undefined,
    pendingEntityIds = [],
    projectionStatus = "ready",
    projectionSource = "revision",
    pinned = false,
    onTogglePin = undefined,
    onUpdate,
  }: Props = $props();
  let fields = $derived(fieldsFor(selectable));
  let topology = $derived(
    selectionTopology(graph, selectable, {
      projection,
      pendingEntityIds,
      projectionSource,
    }),
  );

  function fieldsFor(selectable: Node | Edge): Field[] {
    const contracts: Readonly<Record<string, string>> =
      "view_data" in selectable ? nodeDataContracts : edgeDataContracts;
    const contract = contracts[selectable.type];
    return contract ? fieldsFrom(contract, selectable.data) : [];
  }

  function fieldsFrom(
    contract: string,
    data: unknown,
    path: string[] = [],
  ): Field[] {
    const values =
      data && typeof data === "object" ? (data as Record<string, unknown>) : {};
    const metadataByContract = contractMetadata as Readonly<
      Record<string, ContractMetadata>
    >;
    const fields: Field[] = [];
    for (const metadata of metadataByContract[contract]?.fields ?? []) {
      const value = values[metadata.name];
      if (metadata.kind !== "object") {
        fields.push({ path: [...path, metadata.name], metadata, value });
        continue;
      }
      if (!metadata.contract || !value || typeof value !== "object") continue;
      fields.push(
        ...fieldsFrom(metadata.contract, value, [...path, metadata.name]),
      );
    }
    return fields;
  }

  function update(field: Field, raw: string): void {
    const data = structuredClone(selectable.data) as Record<string, unknown>;
    let target = data;
    for (const key of field.path.slice(0, -1))
      target = target[key] as Record<string, unknown>;
    const key = field.path.at(-1)!;
    if (raw === "" && field.metadata.nullable) {
      target[key] = null;
      onUpdate({ ...selectable, data } as Node | Edge);
      return;
    }
    if (raw === "" && field.metadata.kind === "number") return;
    if (field.metadata.kind === "number") target[key] = Number(raw);
    else target[key] = raw;
    onUpdate({ ...selectable, data } as Node | Edge);
  }

  function errorsFor(field: Field, includeNested = false): readonly string[] {
    return errors
      .filter(
        (error) =>
          pathsEqual(error.field_path, field.path) ||
          (includeNested && pathStartsWith(error.field_path, field.path)),
      )
      .map((error) => error.message);
  }
</script>

<Inspector title={selectable.type}>
  {#if onTogglePin && "view_data" in selectable}
    <button
      type="button"
      class="pin-action"
      class:is-pinned={pinned}
      aria-pressed={pinned}
      onclick={() => onTogglePin?.(selectable.id)}
    >
      {pinned ? "Unpin" : "Pin"}
      {selectable.type}
    </button>
  {/if}
  <form class="selection-fields" onsubmit={(event) => event.preventDefault()}>
    {#each fields as field (JSON.stringify(field.path))}
      {@const presentation = fieldPresentation(
        selectable.type,
        field.path,
        field.metadata.kind,
      )}
      {@const fieldErrors = errorsFor(
        field,
        presentation.custom === "requiredFlows",
      )}
      {#if presentation.custom === "requiredFlows" && selectable.type === "MissionCapability"}
        <RequiredFlowsField
          selectable={selectable as MissionCapabilityNode}
          {graph}
          {projection}
          {projectionSource}
          {canEditFlows}
          errors={fieldErrors}
          {onUpdate}
        />
      {/if}
      {#if !presentation.custom && !presentation.hidden && (field.metadata.kind === "enum" || field.metadata.kind === "string" || field.metadata.kind === "number")}
        <SelectionScalarField
          metadata={field.metadata}
          label={presentation.label}
          value={field.value}
          errors={fieldErrors}
          onchange={(value) => update(field, value)}
        />
      {/if}
    {/each}
  </form>
  {#if topology.placement}
    <section
      class="inspector-section"
      data-placement-status={topology.placement.status}
      data-placement-reason={topology.placement.reasonCode}
    >
      <h3>Placement</h3>
      <p class="placement-reason">{topology.placement.reason}</p>
    </section>
  {/if}
  {#if projectionStatus === "pending"}
    <section class="inspector-section" data-projection-status="pending">
      <h3>Topology</h3>
      <p>Updating grouping. Graph editing remains available.</p>
    </section>
  {/if}
  {#if projectionStatus === "error"}
    <section class="inspector-section" data-projection-status="error">
      <h3>Topology</h3>
      <p>Topology grouping is unavailable. Graph editing remains available.</p>
    </section>
  {/if}
  {#if topology.relationships.length > 0}
    <section class="inspector-section" data-relationships="true">
      <h3>Relationships</h3>
      <ul>
        {#each topology.relationships as relationship (relationship)}
          <li>{relationship}</li>
        {/each}
      </ul>
    </section>
  {/if}
  {#if topology.draftReachability}
    <section class="inspector-section" data-draft-reachability="true">
      <h3>Reachability</h3>
      <p>Draft reachability · Save before simulation</p>
    </section>
  {/if}
</Inspector>

<style>
  .selection-fields {
    display: grid;
    gap: var(--ui-space-3);
  }
  .pin-action {
    width: 100%;
    min-height: var(--ui-control-height);
    margin-bottom: var(--ui-space-3);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-surface);
    color: var(--ui-color-text);
    font: inherit;
  }
  .pin-action:hover {
    background: var(--ui-color-accent-soft);
  }
  .pin-action.is-pinned {
    border-color: var(--ui-color-accent);
    background: var(--ui-color-accent-soft);
    font-weight: 700;
  }
  .pin-action:focus-visible {
    outline: 2px solid var(--ui-color-focus);
    outline-offset: 1px;
  }
  .inspector-section {
    margin-top: var(--ui-space-4);
    padding-top: var(--ui-space-3);
    border-top: 1px solid var(--ui-color-border-soft);
  }
  .inspector-section h3 {
    margin: 0 0 var(--ui-space-2);
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    font-weight: 600;
    letter-spacing: 0.05em;
    text-transform: uppercase;
  }
  .inspector-section p,
  .inspector-section ul {
    margin: 0;
    font-size: var(--ui-text-sm);
  }
  .inspector-section ul {
    display: grid;
    gap: var(--ui-space-1);
    padding-left: var(--ui-space-3);
  }
  .placement-reason {
    color: var(--ui-color-warning-text);
  }
</style>
