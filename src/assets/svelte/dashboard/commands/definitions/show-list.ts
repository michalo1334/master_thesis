import { hasTopologyDocument } from "../helpers";
import type { CommandDefinition } from "../types";

export const showList = {
  id: "show-list",
  label: "List view",
  icon: "list",
  isAvailable: hasTopologyDocument,
  execute: (context) => context.setUi({ presentation: "list" }),
} satisfies CommandDefinition<"show-list">;
