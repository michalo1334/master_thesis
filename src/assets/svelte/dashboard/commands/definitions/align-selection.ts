import { hasSelection, recordSelectionAction } from "../helpers";
import type { CommandDefinition } from "../types";

export const alignSelection = {
  id: "align-selection",
  label: "Align",
  icon: "align",
  undo: { label: "Align selection" },
  isAvailable: hasSelection,
  execute: (context) => recordSelectionAction(context, "align"),
} satisfies CommandDefinition<"align-selection">;
