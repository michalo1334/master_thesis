<script lang="ts" generics="Item">
  import { Dialog } from "bits-ui";
  import FilterableTable from "../controls/FilterableTable.svelte";
  import type { FilterableTableColumn } from "../controls/FilterableTable.types";

  interface Props {
    items: readonly Item[];
    title: string;
    description?: string;
    getKey: (item: Item) => string;
    columns: readonly FilterableTableColumn<Item>[];
    searchPlaceholder?: string;
    perPage?: number;
    isDisabled?: (item: Item) => boolean;
    mode: "single" | "multiple";
    initialSelection: readonly string[];
    minSelections: number;
    emptyMessage: string;
    noMatchMessage: string;
    status: string;
    onConfirm: (items: Item[]) => boolean | Promise<boolean>;
    onClose: () => void;
  }

  let {
    items,
    title,
    description = undefined,
    getKey,
    columns,
    searchPlaceholder = "Search…",
    perPage = 8,
    isDisabled = undefined,
    mode,
    initialSelection,
    minSelections,
    emptyMessage,
    noMatchMessage,
    status,
    onConfirm,
    onClose,
  }: Props = $props();

  let isConfirming = $state(false);
  let confirmationError = $state("");
  let draftKeys = $state<string[]>([]);
  let initialSeeded = $state(false);

  $effect(() => {
    if (initialSeeded) return;
    initialSeeded = true;
    const enabledKeys = new Set(
      items.filter((item) => !isDisabled?.(item)).map((item) => getKey(item)),
    );
    const valid = [...new Set(initialSelection)].filter((key) =>
      enabledKeys.has(key),
    );
    draftKeys = mode === "single" ? valid.slice(0, 1) : valid;
  });

  const selectedItems = $derived(
    items.filter((item) => draftKeys.includes(getKey(item))),
  );
  const displayStatus = $derived(status || confirmationError);
  const canConfirm = $derived(
    !isConfirming && selectedItems.length >= minSelections,
  );

  async function handleConfirm(): Promise<void> {
    if (!canConfirm) return;

    isConfirming = true;
    confirmationError = "";

    try {
      if (await onConfirm(selectedItems)) {
        onClose();
      }
    } catch {
      if (!status) {
        confirmationError =
          "Unable to complete the selection. Please try again.";
      }
    } finally {
      isConfirming = false;
    }
  }
</script>

<Dialog.Portal>
  <Dialog.Overlay class="option-picker-overlay" />
  <Dialog.Content class="option-picker-dialog">
    <Dialog.Title>{title}</Dialog.Title>
    {#if description}
      <Dialog.Description>{description}</Dialog.Description>
    {/if}

    <div class="option-picker-body">
      <FilterableTable
        {items}
        {columns}
        {getKey}
        selectionMode={mode}
        bind:selectedKeys={draftKeys}
        initialSelectedKeys={initialSelection}
        {isDisabled}
        {perPage}
        {searchPlaceholder}
        {emptyMessage}
        {noMatchMessage}
        disabled={isConfirming}
      />
    </div>

    {#if displayStatus}
      <p class="option-picker-status" role="alert">{displayStatus}</p>
    {/if}

    <div class="option-picker-actions">
      <Dialog.Close
        class="option-picker-button option-picker-cancel"
        disabled={isConfirming}
      >
        Cancel
      </Dialog.Close>
      <button
        class="option-picker-button option-picker-confirm"
        type="button"
        disabled={!canConfirm}
        onclick={handleConfirm}
      >
        {mode === "multiple" ? `Select (${selectedItems.length})` : "Select"}
      </button>
    </div>
  </Dialog.Content>
</Dialog.Portal>

<style>
  :global(.option-picker-overlay) {
    position: fixed;
    z-index: 200;
    inset: 0;
    background: color-mix(in srgb, var(--ds-color-nav) 45%, transparent);
  }

  :global(.option-picker-dialog) {
    position: fixed;
    z-index: 201;
    top: 50%;
    left: 50%;
    width: min(40rem, calc(100vw - 2rem));
    max-height: min(40rem, calc(100dvh - 2rem));
    display: grid;
    grid-template-rows: auto auto minmax(0, 1fr) auto auto;
    padding: 1.5rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-lg);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-md);
    color: var(--ds-color-text);
    transform: translate(-50%, -50%);
  }

  :global(.option-picker-dialog [data-dialog-title]) {
    margin: 0;
    font-size: var(--ds-text-xl);
  }

  :global(.option-picker-dialog [data-dialog-description]) {
    margin: var(--ds-space-2) 0 0;
    color: var(--ds-color-text-secondary);
  }

  .option-picker-body {
    min-height: 0;
    margin-top: var(--ds-space-4);
  }

  .option-picker-status {
    margin: var(--ds-space-3) 0 0;
    padding: var(--ds-space-2) var(--ds-space-3);
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-warning-bg);
    color: var(--ds-color-warning-text);
    font-size: var(--ds-text-sm);
  }

  .option-picker-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--ds-space-2);
    margin-top: var(--ds-space-4);
  }

  :global(.option-picker-button) {
    min-height: var(--ds-control-height);
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-surface);
    color: inherit;
  }

  :global(.option-picker-confirm) {
    border-color: var(--ds-color-accent);
    background: var(--ds-color-accent);
    color: var(--ds-color-paper);
  }

  :global(.option-picker-button:not(:disabled):hover) {
    filter: brightness(0.96);
  }

  :global(.option-picker-button:disabled) {
    cursor: default;
    opacity: 0.55;
  }
</style>
