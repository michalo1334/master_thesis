<script lang="ts">
  import type { Snippet } from "svelte";

  interface Props {
    title: string;
    children: Snippet;
  }

  let { title, children }: Props = $props();
</script>

<div class="dashboard-ribbon-group">
  {@render children()}
  <span class="dashboard-ribbon-group-label">{title}</span>
</div>
