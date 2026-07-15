import { hasSelection, recordSelectionAction } from "../helpers";
import type { CommandDefinition } from "../types";

export const lockSelection = {
  id: "lock-selection",
  label: "Lock",
  icon: "lock",
  undo: { label: "Lock selection" },
  isAvailable: hasSelection,
  execute: (context) => recordSelectionAction(context, "lock"),
} satisfies CommandDefinition<"lock-selection">;
