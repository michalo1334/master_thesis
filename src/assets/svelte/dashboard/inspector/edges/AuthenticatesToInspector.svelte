<script lang="ts">
  import type { AuthenticatesToEdge } from "../../../contracts.generated/graph";

  import Inspector from "../../../ui-kit/layout/Inspector.svelte";
  import InspectorField from "../../../ui-kit/layout/InspectorField.svelte";

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
