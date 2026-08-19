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
    margin-top: var(--ui-space-6);
    padding: var(--ui-space-4);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-lg);
    background: var(--ui-color-paper);
  }
  h2,
  h3,
  p,
  ul {
    margin: 0;
  }
  h2 {
    font-size: var(--ui-text-base);
  }
  p,
  li {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }
  p,
  h3,
  ul {
    margin-top: var(--ui-space-2);
  }
  h3 {
    font-size: var(--ui-text-sm);
  }
  ul {
    padding-left: 1.25rem;
  }
</style>
