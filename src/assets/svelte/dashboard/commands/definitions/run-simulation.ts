import { hasTopologyDocument, serverPayload } from "../helpers";
import type { CommandDefinition } from "../types";

export const runSimulation = {
  id: "run-simulation",
  label: "Simulate",
  icon: "play",
  isAvailable: hasTopologyDocument,
  execute: (context) =>
    context.live?.pushEvent("run_simulation", serverPayload(context)),
} satisfies CommandDefinition<"run-simulation">;
