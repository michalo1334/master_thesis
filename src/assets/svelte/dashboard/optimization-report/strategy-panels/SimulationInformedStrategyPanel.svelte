<script lang="ts">
  import type { OptimizationPresentation } from "../optimization-presentation";
  import StrategyPanel from "./StrategyPanel.svelte";
  interface Props {
    presentation: OptimizationPresentation;
  }
  let { presentation }: Props = $props();
</script>

<StrategyPanel
  title="Simulation-informed prioritization"
  description="Ranks defenses by simulated blast-radius reduction."
  actions={presentation.actions}
/>
