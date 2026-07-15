import { hasTopologyDocument } from "../helpers";
import type { CommandDefinition } from "../types";

export const setTopologyLayout = {
  id: "set-topology-layout",
  label: "Set topology layout",
  isAvailable: hasTopologyDocument,
  execute: (context, { layout }) => context.setUi({ topologyLayout: layout }),
} satisfies CommandDefinition<"set-topology-layout">;
