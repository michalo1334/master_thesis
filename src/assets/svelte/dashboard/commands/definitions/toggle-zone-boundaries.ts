import { hasTopologyDocument } from "../helpers";
import type { CommandDefinition } from "../types";

export const toggleZoneBoundaries = {
  id: "toggle-zone-boundaries",
  label: "Toggle zone boundaries",
  icon: "zone",
  isAvailable: hasTopologyDocument,
  execute: (context) =>
    context.setUi({ showZoneBoundaries: !context.ui.showZoneBoundaries }),
} satisfies CommandDefinition<"toggle-zone-boundaries">;
