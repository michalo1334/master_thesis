<script lang="ts">
  import type { Selectable } from "../contract";
  import Inspector from "./Inspector.svelte";
  import InspectorField from "./InspectorField.svelte";

  interface Props {
    selectable: Selectable;
  }

  let { selectable }: Props = $props();
</script>

<Inspector title="Vulnerability">
  <InspectorField fields={[{ label: "Nothing selected", value: "" }]} />
</Inspector>
