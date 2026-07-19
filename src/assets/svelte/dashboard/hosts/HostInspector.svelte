<script lang="ts">
  import type { HostNode } from "../contracts.generated";
  import Inspector from "../workspace/Inspector.svelte";
  import InspectorField from "../workspace/InspectorField.svelte";

  interface Props {
    selectable: HostNode;
  }

  let { selectable }: Props = $props();
</script>

<Inspector title="Host">
  <InspectorField fields={[{ label: "Name", value: selectable.data.name }]} />
</Inspector>
