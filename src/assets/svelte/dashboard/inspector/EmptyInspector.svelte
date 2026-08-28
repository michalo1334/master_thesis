<script lang="ts">
  import type { Edge, Node } from "../../contracts.generated/graph";

  import Inspector from "../../ui-kit/layout/Inspector.svelte";
  import InspectorField from "../../ui-kit/layout/InspectorField.svelte";

  interface Props {
    selectable: Node | Edge;
  }

  let { selectable }: Props = $props();
</script>

<Inspector title="Vulnerability">
  <InspectorField fields={[{ label: "Nothing selected", value: "" }]} />
</Inspector>
