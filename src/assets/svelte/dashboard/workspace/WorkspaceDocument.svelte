<script lang="ts">
  import { Tabs } from "bits-ui";
  import { onMount } from "svelte";
  import type { Snippet } from "svelte";
  import { getWorkspaceContext } from "./workspace-context";

  interface Props {
    id: string;
    title: string;
    children: Snippet;
  }

  let { id, title, children }: Props = $props();
  const workspace = getWorkspaceContext();

  onMount(() => workspace.registerDocument({ id, title: () => title }));
</script>

<Tabs.Content class="dashboard-document-panel" value={id}>
  {@render children()}
</Tabs.Content>
