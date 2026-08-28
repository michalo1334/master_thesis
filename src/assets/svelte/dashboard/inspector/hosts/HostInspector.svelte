<script lang="ts">
  import type { HostNode } from "../../../contracts.generated/graph";

  import Inspector from "../../../ui-kit/layout/Inspector.svelte";
  import InspectorField from "../../../ui-kit/layout/InspectorField.svelte";

  interface Props {
    selectable: HostNode;
  }

  let { selectable }: Props = $props();
</script>

<Inspector title="Host">
  <InspectorField fields={[{ label: "Name", value: selectable.data.name }]} />
</Inspector>
