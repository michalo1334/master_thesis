<script lang="ts">
  import type { Selectable } from "../../../contract";
  import Inspector from "../../../../ui-kit/layout/Inspector.svelte";
  import InspectorField from "../../../../ui-kit/layout/InspectorField.svelte";

  interface Props {
    selectable: Selectable;
  }

  let { selectable }: Props = $props();

  let edge = $derived(!("view_data" in selectable) ? selectable : null);
</script>

{#if edge}
  <Inspector title="Edge inspector">
    <InspectorField
      fields={[
        { label: "ID", value: edge.id },
        { label: "Type", value: edge.type },
        { label: "From", value: edge.from_id },
        { label: "To", value: edge.to_id },
      ]}
    />
  </Inspector>
{/if}
