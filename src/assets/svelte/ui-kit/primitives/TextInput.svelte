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

<div class="text-field">
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
    gap: var(--ui-space-1);
    min-width: 0;
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }
  input {
    width: 100%;
    min-width: 0;
    padding: var(--ui-space-2);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-sm);
    background: var(--ui-color-paper);
    color: var(--ui-color-text);
  }
  input:focus-visible {
    outline: 2px solid var(--ui-color-accent);
    outline-offset: 2px;
  }
  input[aria-invalid="true"] {
    border-color: var(--ui-color-danger);
  }
  input:disabled {
    opacity: 0.6;
  }
</style>
