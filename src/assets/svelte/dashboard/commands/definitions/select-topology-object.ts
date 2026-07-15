import { hasTopologyDocument } from "../helpers";
import type { CommandDefinition } from "../types";

export const selectTopologyObject = {
  id: "select-topology-object",
  label: "Select topology object",
  icon: "cursor",
  isAvailable: hasTopologyDocument,
  execute: (context, { object }) => context.setSelectedObject(object),
} satisfies CommandDefinition<"select-topology-object">;
