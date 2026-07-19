<script lang="ts">
  import type { Snippet } from "svelte";
  import type { HTMLButtonAttributes } from "svelte/elements";

  interface Props extends HTMLButtonAttributes {
    variant?: "large" | "small";
    children?: Snippet;
  }

  let {
    variant = "large",
    children,
    class: className,
    type,
    ...attributes
  }: Props = $props();
</script>

<button
  {...attributes}
  class={[
    "dashboard-button",
    variant === "small" && "dashboard-button-small",
    className,
  ]}
  type={type ?? "button"}
>
  {@render children?.()}
</button>

<style>
  .dashboard-button {
    min-width: 3.125rem;
    min-height: 3.875rem;
    padding: 0.3125rem 0.4375rem;
    border: 1px solid transparent;
    border-radius: var(--ds-radius-md);
    background: transparent;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--ds-space-1);
    --dashboard-icon-color: var(--ds-color-accent);
  }

  .dashboard-button:not(:disabled):hover,
  .dashboard-button[aria-pressed="true"]:not(:disabled) {
    background: var(--ds-color-accent-soft);
    border-color: var(--ds-color-accent-soft);
  }

  .dashboard-button:disabled {
    cursor: default;
  }

  .dashboard-button-small {
    min-width: 4.625rem;
    min-height: var(--ds-control-height);
    flex-direction: row;
    justify-content: flex-start;
  }
</style>
