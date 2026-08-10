<script lang="ts">
  import type { MissionCapabilityNode } from "../../../contracts.generated";
  import Inspector from "../Inspector.svelte";
  import InspectorField from "../InspectorField.svelte";

  interface Props {
    selectable: MissionCapabilityNode;
  }

  let { selectable }: Props = $props();
</script>

<Inspector title="Mission capability">
  <InspectorField
    fields={[
      { label: "Name", value: selectable.data.name },
      { label: "Description", value: selectable.data.description ?? "—" },
      { label: "Impact weight", value: String(selectable.data.impact_weight) },
      {
        label: "Minimum operational support",
        value: String(selectable.data.min_operational_support),
      },
    ]}
  />
</Inspector>
