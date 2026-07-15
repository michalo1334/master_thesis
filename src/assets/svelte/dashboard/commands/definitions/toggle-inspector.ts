import type { CommandDefinition } from "../types";

export const toggleInspector = {
  id: "toggle-inspector",
  label: "Toggle inspector",
  icon: "chevron-right",
  isAvailable: () => true,
  execute: (context) =>
    context.setUi({ inspectorVisible: !context.ui.inspectorVisible }),
} satisfies CommandDefinition<"toggle-inspector">;
