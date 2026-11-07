<script lang="ts">
  import type { StudyDocument } from "./StudyDocument.svelte";
  import Inspector from "../../ui-kit/layout/Inspector.svelte";
  import InspectorField from "../../ui-kit/layout/InspectorField.svelte";
  let { document }: { document: StudyDocument } = $props();
</script>

<Inspector title="Study context">
  <InspectorField
    fields={[
      {
        label: "Revision",
        value: document.revision
          ? `${document.revision.study_id} r${document.revision.revision}`
          : "Editable draft",
      },
      {
        label: "Execution",
        value: document.selectedExecutionId ?? "None selected",
      },
      {
        label: "Accepted state",
        value: document.selectedExecution?.status?.state ?? "Unavailable",
      },
      {
        label: "Measurement label",
        value: String(
          document.detail?.context.measurement_label ??
            document.definition.options?.measurement_label ??
            "Unavailable",
        ),
      },
    ]}
  />
  {#if document.selectedRow}<h3>Selected comparison</h3>
    <pre>{JSON.stringify(document.selectedRow, null, 2)}</pre>{/if}
</Inspector>

<style>
  h3 {
    font-size: var(--ui-text-sm);
  }
  pre {
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    font-size: var(--ui-text-xs);
  }
</style>
