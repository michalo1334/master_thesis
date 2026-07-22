<script lang="ts" generics="Item">
  import { Checkbox, Dialog, RadioGroup } from "bits-ui";

  interface Props {
    items: readonly Item[];
    title: string;
    description?: string;
    getKey: (item: Item) => string;
    getTitle: (item: Item) => string;
    getDescription?: (item: Item) => string | undefined;
    isDisabled?: (item: Item) => boolean;
    mode: "single" | "multiple";
    initialSelection: readonly string[];
    minSelections: number;
    emptyMessage: string;
    status: string;
    onConfirm: (items: Item[]) => boolean | Promise<boolean>;
    onClose: () => void;
  }

  let {
    items,
    title,
    description = undefined,
    getKey,
    getTitle,
    getDescription = undefined,
    isDisabled = undefined,
    mode,
    initialSelection,
    minSelections,
    emptyMessage,
    status,
    onConfirm,
    onClose,
  }: Props = $props();

  let isConfirming = $state(false);
  let confirmationError = $state("");
  let content = $state<HTMLDivElement | null>(null);
  let draftKeys = $state(getValidInitialSelection() ?? []);

  const selectedItems = $derived(
    items.filter((item) => draftKeys.includes(getKey(item))),
  );
  const displayStatus = $derived(status || confirmationError);
  const canConfirm = $derived(
    !isConfirming && selectedItems.length >= minSelections,
  );

  function getValidInitialSelection(): string[] | undefined {
    const enabledKeys = new Set(
      items.filter((item) => !isDisabled?.(item)).map((item) => getKey(item)),
    );
    const keys = [...new Set(initialSelection)].filter((key) =>
      enabledKeys.has(key),
    );

    return mode === "single" ? keys.slice(0, 1) : keys;
  }

  function getSingleSelection(): string {
    return draftKeys[0] ?? "";
  }

  function setSingleSelection(key: string): void {
    draftKeys = key ? [key] : [];
  }

  function getMultipleSelection(): string[] {
    return draftKeys;
  }

  function setMultipleSelection(keys: string[]): void {
    draftKeys = keys;
  }

  function focusFirstSelectable(event: Event): void {
    event.preventDefault();
    content
      ?.querySelector<HTMLButtonElement>(
        "[data-option-picker-option]:not(:disabled)",
      )
      ?.focus();
  }

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
  <Dialog.Content
    bind:ref={content}
    class="option-picker-dialog"
    onOpenAutoFocus={focusFirstSelectable}
  >
    <Dialog.Title>{title}</Dialog.Title>
    {#if description}
      <Dialog.Description>{description}</Dialog.Description>
    {/if}

    <div class="option-picker-list" aria-label={title}>
      {#if items.length === 0}
        <p class="option-picker-empty">{emptyMessage}</p>
      {:else if mode === "single"}
        <RadioGroup.Root
          bind:value={getSingleSelection, setSingleSelection}
          aria-label={title}
        >
          {#each items as item (getKey(item))}
            {@const disabled = isDisabled?.(item) ?? false}
            <RadioGroup.Item
              class="option-picker-row"
              data-option-picker-option
              value={getKey(item)}
              disabled={disabled || isConfirming}
            >
              <span class="option-picker-control" aria-hidden="true"></span>
              <span class="option-picker-item">
                <span class="option-picker-item-title">{getTitle(item)}</span>
                {#if getDescription?.(item)}
                  <span class="option-picker-item-description">
                    {getDescription(item)}
                  </span>
                {/if}
              </span>
            </RadioGroup.Item>
          {/each}
        </RadioGroup.Root>
      {:else}
        <Checkbox.Group
          bind:value={getMultipleSelection, setMultipleSelection}
          aria-label={title}
        >
          {#each items as item (getKey(item))}
            {@const disabled = isDisabled?.(item) ?? false}
            <Checkbox.Root
              class="option-picker-row"
              data-option-picker-option
              value={getKey(item)}
              disabled={disabled || isConfirming}
            >
              <span class="option-picker-control" aria-hidden="true"></span>
              <span class="option-picker-item">
                <span class="option-picker-item-title">{getTitle(item)}</span>
                {#if getDescription?.(item)}
                  <span class="option-picker-item-description">
                    {getDescription(item)}
                  </span>
                {/if}
              </span>
            </Checkbox.Root>
          {/each}
        </Checkbox.Group>
      {/if}
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
    width: min(36rem, calc(100vw - 2rem));
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

  .option-picker-list {
    min-height: 0;
    margin-top: var(--ds-space-4);
    overflow-y: auto;
  }

  :global(.option-picker-list [data-radio-group-root]),
  :global(.option-picker-list [data-checkbox-group]) {
    display: grid;
    gap: var(--ds-space-2);
  }

  :global(.option-picker-row) {
    width: 100%;
    min-height: var(--ds-control-height);
    padding: var(--ds-space-3);
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-surface);
    color: inherit;
    text-align: left;
    display: flex;
    align-items: flex-start;
    gap: var(--ds-space-3);
  }

  :global(.option-picker-row:not(:disabled):hover) {
    border-color: var(--ds-color-focus);
    background: var(--ds-color-accent-soft);
  }

  :global(.option-picker-row:disabled) {
    cursor: not-allowed;
    color: var(--ds-color-text-faint);
    opacity: 0.65;
  }

  .option-picker-control {
    width: 1.125rem;
    height: 1.125rem;
    flex: none;
    margin-top: 0.125rem;
    border: 1px solid var(--ds-color-border);
    background: var(--ds-color-paper);
  }

  :global(.option-picker-row[data-radio-group-item]) .option-picker-control {
    border-radius: 50%;
  }

  :global(.option-picker-row[data-checkbox-root]) .option-picker-control {
    border-radius: var(--ds-radius-sm);
  }

  :global(.option-picker-row[data-state="checked"]) .option-picker-control {
    border-color: var(--ds-color-accent);
    background: var(--ds-color-accent);
    box-shadow: inset 0 0 0 0.25rem var(--ds-color-paper);
  }

  :global(.option-picker-row[data-checkbox-root][data-state="checked"])
    .option-picker-control {
    box-shadow: inset 0 0 0 0.25rem var(--ds-color-accent);
  }

  .option-picker-item {
    display: grid;
    min-width: 0;
    gap: var(--ds-space-1);
  }

  .option-picker-item-title {
    font-weight: 600;
  }

  .option-picker-item-description {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
    font-variant-numeric: tabular-nums;
  }

  .option-picker-empty {
    margin: 0;
    padding: var(--ds-space-4);
    color: var(--ds-color-text-secondary);
    text-align: center;
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
