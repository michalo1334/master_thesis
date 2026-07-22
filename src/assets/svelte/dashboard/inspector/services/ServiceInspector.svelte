<script lang="ts">
  import type { ServiceNode } from "../../contracts.generated";
  import Inspector from "../Inspector.svelte";
  import InspectorField from "../InspectorField.svelte";

  interface Props {
    selectable: ServiceNode;
  }

  let { selectable }: Props = $props();
</script>

<Inspector title="Service">
  <InspectorField
    fields={[
      { label: "Name", value: selectable.data.name },
      { label: "Protocol", value: selectable.data.protocol },
      { label: "Port", value: String(selectable.data.port) },
      { label: "Version", value: selectable.data.version ?? "—" },
    ]}
  />
</Inspector>
