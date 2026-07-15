import { hasTopologyDocument, serverPayload } from "../helpers";
import type { CommandDefinition } from "../types";

export const optimizeDefense = {
  id: "optimize-defense",
  label: "Optimize",
  icon: "shield",
  isAvailable: hasTopologyDocument,
  execute: (context) =>
    context.live?.pushEvent("optimize_defense", serverPayload(context)),
} satisfies CommandDefinition<"optimize-defense">;
