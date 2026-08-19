<script lang="ts">
  interface Props {
    fields: Array<{ label: string; value: string }>;
  }

  let { fields }: Props = $props();
</script>

<dl class="inspector-field-list">
  {#each fields as field (field.label)}
    <div class="inspector-field-item">
      <dt>{field.label}</dt>
      <dd>{field.value}</dd>
    </div>
  {/each}
</dl>

<style>
  .inspector-field-list {
    margin: 0;
    display: grid;
    gap: var(--ui-space-3);
  }
  .inspector-field-item {
    display: grid;
    gap: var(--ui-space-1);
  }
  .inspector-field-item dt {
    font-size: var(--ui-text-xs);
    font-weight: 600;
    color: var(--ui-color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .inspector-field-item dd {
    margin: 0;
    font-family: var(--ui-font-mono);
    font-size: var(--ui-text-sm);
    word-break: break-all;
  }
</style>
