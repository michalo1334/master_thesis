import { hasSelection, recordSelectionAction } from "../helpers";
import type { CommandDefinition } from "../types";

export const duplicateSelection = {
  id: "duplicate-selection",
  label: "Duplicate",
  icon: "copy",
  undo: { label: "Duplicate selection" },
  isAvailable: hasSelection,
  execute: (context) => recordSelectionAction(context, "duplicate"),
} satisfies CommandDefinition<"duplicate-selection">;
