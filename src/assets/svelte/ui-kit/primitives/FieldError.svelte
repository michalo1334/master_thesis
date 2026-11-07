<script lang="ts">
  let { error, id }: { error?: string; id?: string } = $props();
</script>

{#if error}<p {id} class="field-error">{error}</p>{/if}

<style>
  .field-error {
    margin: 0;
    color: var(--ui-color-danger);
    font-size: var(--ui-text-xs);
    white-space: pre-line;
    overflow-wrap: anywhere;
  }
</style>
