<script lang="ts">
  import type { OptimizationPresentation } from "../optimization-presentation";
  import StrategyPanel from "./StrategyPanel.svelte";
  interface Props {
    presentation: OptimizationPresentation;
  }
  let { presentation }: Props = $props();
</script>

<StrategyPanel
  title="Simulated annealing"
  description="Searches defense combinations for a lower simulated blast radius."
  actions={presentation.actions}
/>
