<script lang="ts">
  import Inspector from "./workspace/Inspector.svelte";

  interface Props {
    selectedObject?: { id: string; name: string };
  }

  let { selectedObject }: Props = $props();
</script>

<Inspector title="Object inspector">
  <p class="dashboard-inspector-empty">
    {selectedObject
      ? selectedObject.name
      : "The active canvas has no selected objects."}
  </p>
</Inspector>

<style>
  .dashboard-inspector-empty {
    margin: 0;
    color: var(--ds-color-text-faint);
  }
</style>
