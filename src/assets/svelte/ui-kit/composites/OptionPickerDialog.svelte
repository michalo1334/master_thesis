<script lang="ts" generics="Item">
  import { Dialog } from "bits-ui";
  import OptionPickerDialogContent from "./OptionPickerDialogContent.svelte";
  import type { FilterableTableColumn } from "./FilterableTable.types";

  interface Props {
    open: boolean;
    onOpenChange: (open: boolean) => void;
    items: readonly Item[];
    title: string;
    description?: string;
    getKey: (item: Item) => string;
    columns: readonly FilterableTableColumn<Item>[];
    searchPlaceholder?: string;
    perPage?: number;
    isDisabled?: (item: Item) => boolean;
    mode?: "single" | "multiple";
    initialSelection?: readonly string[];
    minSelections?: number;
    emptyMessage: string;
    noMatchMessage?: string;
    status?: string;
    onConfirm: (items: Item[]) => boolean | Promise<boolean>;
  }

  let {
    open,
    onOpenChange,
    items,
    title,
    description = undefined,
    getKey,
    columns,
    searchPlaceholder = "Search…",
    perPage = 8,
    isDisabled = undefined,
    mode = "single",
    initialSelection = [],
    minSelections = 1,
    emptyMessage,
    noMatchMessage = "No matches.",
    status = "",
    onConfirm,
  }: Props = $props();
</script>

<Dialog.Root {open} {onOpenChange}>
  {#if open}
    <OptionPickerDialogContent
      {items}
      {title}
      {description}
      {getKey}
      {columns}
      {searchPlaceholder}
      {perPage}
      {isDisabled}
      {mode}
      {initialSelection}
      {minSelections}
      {emptyMessage}
      {noMatchMessage}
      {status}
      {onConfirm}
      onClose={() => onOpenChange(false)}
    />
  {/if}
</Dialog.Root>
