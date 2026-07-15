import { hasSelection } from "../helpers";
import type { CommandDefinition } from "../types";

export const clearSelection = {
  id: "clear-selection",
  label: "Clear selection",
  isAvailable: hasSelection,
  execute: (context) => context.setSelectedObject(),
} satisfies CommandDefinition<"clear-selection">;
