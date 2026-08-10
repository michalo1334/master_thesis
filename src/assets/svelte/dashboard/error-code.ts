import type { ErrorCode } from "./contract";

const messages: Record<ErrorCode, string> = {
  not_found: "The requested item was not found.",
  invalid_graph: "The graph is invalid.",
  invalid_base_revision: "The selected base graph revision is invalid.",
  invalid_node: "The graph contains an invalid node.",
  invalid_edge: "The graph contains an invalid edge.",
  invalid_endpoints: "The connection endpoints are invalid.",
  multiple_segments: "Each host must belong to exactly one network segment.",
  multiple_runs: "Each service must run on exactly one host.",
  invalid_mission_capability_support:
    "Mission capability support requirements are invalid.",
  duplicate_ids: "The graph contains duplicate IDs.",
  identity_belongs_to_another_graph: "An item belongs to another graph.",
  invalid_folder: "The folder is invalid.",
  folder_not_found: "The folder was not found.",
  invalid_initial_foothold: "Select a valid initial foothold.",
  persistence_failed: "Could not save the changes.",
  task_unavailable: "This task is currently unavailable.",
  internal_error: "The operation could not be completed.",
  unknown_strategy: "The selected optimization strategy is not supported.",
  reachability_required: "The graph requires reachability information.",
  invalid_request: "The request is invalid.",
};

export function formatDashboardErrorCode(code: ErrorCode): string {
  return messages[code] ?? messages.internal_error;
}
