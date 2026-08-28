<script lang="ts">
  import type { CredentialNode } from "../../../contracts.generated/graph";

  import Inspector from "../../../ui-kit/layout/Inspector.svelte";
  import InspectorField from "../../../ui-kit/layout/InspectorField.svelte";

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
