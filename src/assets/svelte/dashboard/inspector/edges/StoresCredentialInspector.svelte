<script lang="ts">
  import type { StoresCredentialEdge } from "../../../contracts.generated/graph";

  import Inspector from "../../../ui-kit/layout/Inspector.svelte";
  import InspectorField from "../../../ui-kit/layout/InspectorField.svelte";

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
