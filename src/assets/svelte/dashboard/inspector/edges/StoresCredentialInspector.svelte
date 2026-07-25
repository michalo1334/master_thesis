<script lang="ts">
  import type { StoresCredentialEdge } from "../../contract";
  import Inspector from "../Inspector.svelte";
  import InspectorField from "../InspectorField.svelte";

  interface Props {
    selectable: StoresCredentialEdge;
  }

  let { selectable }: Props = $props();
</script>

<Inspector title="Stores credential">
  <InspectorField
    fields={[
      {
        label: "Required privilege",
        value: selectable.data.required_privilege,
      },
    ]}
  />
</Inspector>
