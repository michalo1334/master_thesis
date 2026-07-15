<script lang="ts">
  import { Tabs } from "bits-ui";
  import { onDestroy } from "svelte";
  import type { Snippet } from "svelte";
  import { getRibbonContext } from "./ribbon-context";

  interface Props {
    title: string;
    children: Snippet;
  }

  let { title, children }: Props = $props();
  let ribbon = getRibbonContext();
  let value = $props.id();
  let unregister = ribbon.registerTab({ title: () => title, value });

  onDestroy(unregister);
</script>

<Tabs.Content class="dashboard-ribbon-panel" {value}>
  {@render children()}
</Tabs.Content>
