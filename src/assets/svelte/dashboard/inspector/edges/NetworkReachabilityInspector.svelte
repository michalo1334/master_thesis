<script lang="ts">
  import type { NetworkReachabilityEdge } from "../../contract";
  import Inspector from "../Inspector.svelte";
  import InspectorField from "../InspectorField.svelte";

  interface Props {
    selectable: NetworkReachabilityEdge;
  }

  let { selectable }: Props = $props();
  let portInterval = $derived(
    `${selectable.data.port_start ?? "any"} - ${selectable.data.port_end ?? "any"}`,
  );
</script>

<Inspector title="Network reachability">
  <InspectorField
    fields={[
      { label: "Protocol", value: selectable.data.protocol },
      { label: "Port interval", value: portInterval },
    ]}
  />
</Inspector>
