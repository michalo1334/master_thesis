<script lang="ts">
  import type { Selectable } from "../contract";
  import Inspector from "../../ui-kit/layout/Inspector.svelte";
  import InspectorField from "../../ui-kit/layout/InspectorField.svelte";

  interface Props {
    selectable: Selectable;
  }

  let { selectable }: Props = $props();
</script>

<Inspector title="Vulnerability">
  <InspectorField fields={[{ label: "Nothing selected", value: "" }]} />
</Inspector>
