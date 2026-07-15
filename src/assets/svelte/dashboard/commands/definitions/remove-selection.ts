import { hasSelection, recordSelectionAction } from "../helpers";
import type { CommandDefinition } from "../types";

export const removeSelection = {
  id: "remove-selection",
  label: "Remove",
  icon: "trash",
  undo: { label: "Remove selection" },
  isAvailable: hasSelection,
  execute: (context) => {
    recordSelectionAction(context, "remove");
    context.setSelectedObject();
  },
} satisfies CommandDefinition<"remove-selection">;
