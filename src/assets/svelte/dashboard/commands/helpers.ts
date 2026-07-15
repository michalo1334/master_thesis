import type { CommandContext, DashboardUiState } from "./types";

export const hasTopologyDocument = (context: CommandContext) =>
  context.activeDocument?.type === "topology";

export const hasSelection = (context: CommandContext) =>
  hasTopologyDocument(context) && Boolean(context.selectedObject);

export function recordSelectionAction(
  context: CommandContext,
  action: NonNullable<DashboardUiState["lastSelectionAction"]>,
) {
  context.setUi({ lastSelectionAction: action });
}

export function serverPayload(context: CommandContext) {
  return {
    document_id: context.activeDocument?.id,
    selected_object_id: context.selectedObject?.id,
    source: context.source,
  };
}
