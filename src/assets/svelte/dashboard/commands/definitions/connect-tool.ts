import { hasTopologyDocument } from "../helpers";
import type { CommandDefinition } from "../types";

export const connectTool = {
  id: "connect-tool",
  label: "Connect",
  icon: "link",
  isAvailable: hasTopologyDocument,
  execute: (context) => context.setUi({ currentTool: "connect" }),
} satisfies CommandDefinition<"connect-tool">;
