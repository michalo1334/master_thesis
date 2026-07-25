<script lang="ts">
  import type { CredentialNode } from "../../contract";
  import Inspector from "../Inspector.svelte";
  import InspectorField from "../InspectorField.svelte";

  interface Props {
    selectable: CredentialNode;
  }

  let { selectable }: Props = $props();
</script>

<Inspector title="Credential">
  <InspectorField
    fields={[
      { label: "Identifier", value: selectable.data.identifier },
      {
        label: "Credential type",
        value: selectable.data.credential_type.replace("_", " "),
      },
    ]}
  />
</Inspector>
