<script lang="ts">
  interface Props {
    errors: readonly string[];
    id?: string;
    class?: string;
  }

  let {
    errors,
    id = undefined,
    class: className = undefined,
  }: Props = $props();
</script>

{#if errors.length}
  <ul {id} class={["error-messages", className]} role="alert">
    {#each errors as error, index (`${error}:${index}`)}
      <li>{error}</li>
    {/each}
  </ul>
{/if}

<style>
  .error-messages {
    display: grid;
    gap: var(--ui-space-1);
    margin: 0;
    padding-left: 1.25rem;
    color: var(--ui-color-danger);
    font-size: var(--ui-text-xs);
  }
</style>
