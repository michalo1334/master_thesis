import { hasTopologyDocument } from "../helpers";
import type { CommandDefinition } from "../types";

export const selectTool = {
  id: "select-tool",
  label: "Select",
  icon: "cursor",
  isAvailable: hasTopologyDocument,
  execute: (context) => context.setUi({ currentTool: "select" }),
} satisfies CommandDefinition<"select-tool">;
