<script lang="ts">
  import type { Selectable } from "../../contract";
  import Inspector from "../../workspace/Inspector.svelte";
  import InspectorField from "../../workspace/InspectorField.svelte";

  interface Props {
    selectable: Selectable;
  }

  let { selectable }: Props = $props();

  let node = $derived("view_data" in selectable ? selectable : null);
</script>

{#if node}
  <Inspector title="Node inspector">
    <InspectorField
      fields={[
        { label: "ID", value: node.id },
        { label: "Type", value: node.type },
      ]}
    />
  </Inspector>
{/if}
