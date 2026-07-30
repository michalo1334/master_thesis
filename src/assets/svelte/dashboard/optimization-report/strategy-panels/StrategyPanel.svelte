<script lang="ts">
  import type { OptimizationAction } from "../../contract";

  interface Props {
    title: string;
    description: string;
    actions?: readonly OptimizationAction[];
  }

  let { title, description, actions = [] }: Props = $props();
</script>

<section class="strategy-panel" aria-label={title}>
  <h2>{title}</h2>
  <p>{description}</p>
  {#if actions.length > 0}
    <h3>Selected defenses</h3>
    <ul>
      {#each actions as action (action.id)}
        <li>{action.label}</li>
      {/each}
    </ul>
  {/if}
</section>

<style>
  .strategy-panel {
    max-width: 62rem;
    margin-top: var(--ds-space-6);
    padding: var(--ds-space-4);
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-lg);
    background: var(--ds-color-paper);
  }
  h2,
  h3,
  p,
  ul {
    margin: 0;
  }
  h2 {
    font-size: var(--ds-text-base);
  }
  p,
  li {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
  }
  p,
  h3,
  ul {
    margin-top: var(--ds-space-2);
  }
  h3 {
    font-size: var(--ds-text-sm);
  }
  ul {
    padding-left: 1.25rem;
  }
</style>
