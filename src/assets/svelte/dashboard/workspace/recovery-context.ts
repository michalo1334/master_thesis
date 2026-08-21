import type { DashboardApi } from "../dashboard-api";
import type { WorkspaceModel } from "./WorkspaceModel.svelte";

export interface DashboardRecoveryContext {
  api: DashboardApi;
  workspace: WorkspaceModel;
}
