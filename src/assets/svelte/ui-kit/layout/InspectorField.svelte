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
    gap: var(--ds-space-3);
  }
  .inspector-field-item {
    display: grid;
    gap: var(--ds-space-1);
  }
  .inspector-field-item dt {
    font-size: var(--ds-text-xs);
    font-weight: 600;
    color: var(--ds-color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .inspector-field-item dd {
    margin: 0;
    font-family: var(--ds-font-mono);
    font-size: var(--ds-text-sm);
    word-break: break-all;
  }
</style>
