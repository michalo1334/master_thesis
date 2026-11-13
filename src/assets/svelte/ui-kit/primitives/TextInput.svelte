<script lang="ts">
  import FieldError from "./FieldError.svelte";
  interface Props {
    label: string;
    value?: string;
    disabled?: boolean;
    inputmode?: "text" | "decimal" | "numeric";
    placeholder?: string;
    error?: string;
    onchange?: (value: string) => void;
  }
  let {
    label,
    value = $bindable(""),
    disabled = false,
    inputmode = "text",
    placeholder = "",
    error = "",
    onchange,
  }: Props = $props();
  const id = $props.id();
  const errorId = `${id}-error`;
</script>

<div class={["text-field", disabled && "disabled"]}>
  <label for={id}>{label}</label>
  <input
    {id}
    type="text"
    {inputmode}
    {disabled}
    {placeholder}
    aria-invalid={error ? "true" : undefined}
    aria-describedby={error ? errorId : undefined}
    bind:value
    oninput={(event) => onchange?.(event.currentTarget.value)}
  />
  <FieldError id={errorId} {error} />
</div>

<style>
  .text-field {
    display: grid;
    align-content: center;
    gap: 0.1875rem;
    min-width: 0;
    padding: 0.1875rem;
  }
  .text-field.disabled {
    opacity: 0.5;
  }
  label {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    font-weight: 600;
  }
  input {
    width: 100%;
    min-width: 0;
    min-height: var(--ui-control-height);
    padding: 0.1875rem 0.5rem;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    color: var(--ui-color-text);
    font: inherit;
  }
  input:not(:disabled):not([aria-invalid="true"]):hover {
    border-color: var(--ui-color-accent);
  }
  input:focus-visible {
    outline: 2px solid var(--ui-color-focus);
    outline-offset: 2px;
  }
  input[aria-invalid="true"] {
    border-color: var(--ui-color-danger);
  }
  input:disabled {
    color: var(--ui-color-text-faint);
    background: var(--ui-color-surface);
    cursor: default;
  }
</style>
