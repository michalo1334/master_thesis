import { hasTopologyDocument } from "../helpers";
import type { CommandDefinition } from "../types";

export const showGraph = {
  id: "show-graph",
  label: "Graph view",
  icon: "graph",
  isAvailable: hasTopologyDocument,
  execute: (context) => context.setUi({ presentation: "graph" }),
} satisfies CommandDefinition<"show-graph">;
