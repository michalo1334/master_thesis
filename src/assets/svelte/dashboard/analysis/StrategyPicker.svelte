<script lang="ts">
  import Checkbox from "../ui/Checkbox.svelte";
  import type { OptimizationStrategy } from "../contract";

  type StrategyOption = {
    id: OptimizationStrategy;
    title: string;
  };

  interface Props {
    options: readonly StrategyOption[];
    selectedStrategies: readonly OptimizationStrategy[];
    hasFoothold: boolean;
    disabled?: boolean;
    onchange: (strategies: OptimizationStrategy[]) => void;
  }

  let {
    options,
    selectedStrategies,
    hasFoothold,
    disabled = false,
    onchange,
  }: Props = $props();

  function changeStrategy(
    strategy: OptimizationStrategy,
    checked: boolean,
  ): void {
    if (!hasFoothold && strategy !== "cvss") return;

    onchange(
      checked
        ? [...new Set([...selectedStrategies, strategy])]
        : selectedStrategies.filter((selected) => selected !== strategy),
    );
  }
</script>

<div class="strategy-picker" aria-label="Strategies">
  {#each options as option (option.id)}
    <Checkbox
      label={option.title}
      checked={selectedStrategies.includes(option.id)}
      disabled={disabled || (!hasFoothold && option.id !== "cvss")}
      onchange={(checked) => changeStrategy(option.id, checked)}
    />
  {/each}
</div>

<style>
  .strategy-picker {
    display: grid;
    gap: var(--ds-space-1);
  }
</style>
