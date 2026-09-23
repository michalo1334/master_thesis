<script lang="ts">
  import type { FieldMetadata } from "../../../contracts.generated/graph/data";
  import Select from "../../../ui-kit/primitives/Select.svelte";
  import ErrorMessages from "../ErrorMessages.svelte";

  interface Props {
    metadata: FieldMetadata;
    label: string;
    value: unknown;
    errors: readonly string[];
    onchange: (value: string) => void;
  }

  let { metadata, label, value, errors, onchange }: Props = $props();
  const inputId = $props.id();
  const errorsId = `${inputId}-errors`;
  let describedBy = $derived(errors.length ? errorsId : undefined);
</script>

<div class="scalar-field">
  {#if metadata.kind === "enum"}
    <Select
      {label}
      value={String(value ?? "")}
      options={(metadata.choices ?? []).map((value) => ({
        value,
        label: value.replaceAll("_", " "),
      }))}
      aria-invalid={errors.length ? "true" : undefined}
      aria-describedby={describedBy}
      {onchange}
    />
  {:else}
    <label for={inputId}>{label}</label>
    <input
      id={inputId}
      aria-invalid={errors.length ? "true" : undefined}
      aria-describedby={describedBy}
      type={metadata.kind === "number" ? "number" : "text"}
      value={value ?? ""}
      step={metadata.kind === "number" ? "any" : undefined}
      onchange={(event) => onchange(event.currentTarget.value)}
    />
  {/if}
  <ErrorMessages {errors} id={errorsId} />
</div>

<style>
  .scalar-field {
    display: grid;
    gap: var(--ui-space-1);
  }
  label {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    font-weight: 600;
    letter-spacing: 0.05em;
    text-transform: uppercase;
  }
  input {
    min-height: var(--ui-control-height);
    min-width: 0;
    padding: 0.375rem 0.5rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-surface);
    color: var(--ui-color-text);
    font: inherit;
  }
  input:focus-visible {
    outline: 2px solid var(--ui-color-focus);
    outline-offset: 1px;
  }
</style>
