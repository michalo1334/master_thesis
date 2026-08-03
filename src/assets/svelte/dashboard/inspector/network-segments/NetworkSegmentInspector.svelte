<script lang="ts">
  import type { NetworkSegmentNode } from "../../../contracts.generated";
  import Inspector from "../Inspector.svelte";
  import InspectorField from "../InspectorField.svelte";

  interface Props {
    selectable: NetworkSegmentNode;
  }

  let { selectable }: Props = $props();
</script>

<Inspector title="Network segment">
  <InspectorField
    fields={[
      { label: "Name", value: selectable.data.name },
      { label: "CIDR", value: selectable.data.cidr ?? "-" },
    ]}
  />
</Inspector>
