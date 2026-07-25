<script lang="ts">
  import type { AuthenticatesToEdge } from "../../contract";
  import Inspector from "../Inspector.svelte";
  import InspectorField from "../InspectorField.svelte";

  interface Props {
    selectable: AuthenticatesToEdge;
  }

  let { selectable }: Props = $props();
</script>

<Inspector title="Authenticates to">
  <InspectorField
    fields={[
      { label: "Granted privilege", value: selectable.data.granted_privilege },
    ]}
  />
</Inspector>
