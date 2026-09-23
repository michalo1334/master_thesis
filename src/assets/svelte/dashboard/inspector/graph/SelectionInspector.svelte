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
  import type { DashboardApi } from "../../dashboard-api";
  import Inspector from "../../../ui-kit/layout/Inspector.svelte";
  import SelectionScalarField from "./SelectionScalarField.svelte";
  import RequiredFlowsField from "../mission-capabilities/RequiredFlowsField.svelte";
  import { fieldPresentation } from "./selection-inspector-presentation";
  import { pathStartsWith, pathsEqual } from "./validation-path";

  interface Field {
    path: string[];
    metadata: FieldMetadata;
    value: unknown;
  }

  interface Props {
    selectable: Node | Edge;
    graph: GraphContract;
    api: DashboardApi;
    revisionId?: string | null;
    canEditFlows: boolean;
    errors?: readonly GraphValidationError[];
    onUpdate: (selectable: Node | Edge) => void;
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
  let fields = $derived(fieldsFor(selectable));

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
          {api}
          {revisionId}
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
</Inspector>

<style>
  .selection-fields {
    display: grid;
    gap: var(--ui-space-3);
  }
</style>
