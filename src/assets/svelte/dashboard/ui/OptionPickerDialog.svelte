<script lang="ts" generics="Item">
  import { Dialog } from "bits-ui";
  import OptionPickerDialogContent from "./OptionPickerDialogContent.svelte";

  interface Props {
    open: boolean;
    onOpenChange: (open: boolean) => void;
    items: readonly Item[];
    title: string;
    description?: string;
    getKey: (item: Item) => string;
    getTitle: (item: Item) => string;
    getDescription?: (item: Item) => string | undefined;
    isDisabled?: (item: Item) => boolean;
    mode?: "single" | "multiple";
    initialSelection?: readonly string[];
    minSelections?: number;
    emptyMessage: string;
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
    getTitle,
    getDescription = undefined,
    isDisabled = undefined,
    mode = "single",
    initialSelection = [],
    minSelections = 1,
    emptyMessage,
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
      {getTitle}
      {getDescription}
      {isDisabled}
      {mode}
      {initialSelection}
      {minSelections}
      {emptyMessage}
      {status}
      {onConfirm}
      onClose={() => onOpenChange(false)}
    />
  {/if}
</Dialog.Root>
