import type {
  OptimizationParams,
  SimulationSettings,
} from "../contracts.generated/optimization";

// Local optimization form state: the typed request fields plus the dashboard-only seed switch.
export type DashboardOptimizationParams = OptimizationParams & {
  simulation_params: SimulationSettings;
  generate_seed: boolean;
};

export type OptimizationParamsChange = Omit<
  Partial<DashboardOptimizationParams>,
  "simulation_params"
> & {
  simulation_params?: Partial<SimulationSettings>;
};

export const DEFAULT_RULES: SimulationSettings["rules"] = [
  "remote_service_exploitation",
  "local_vulnerability_exploitation",
  "acquire_credential_rule",
  "reuse_credential_rule",
];

export const DEFAULT_CANDIDATE_ACTION_TYPES: OptimizationParams["candidate_action_types"] =
  ["block_segment_reachability", "patch_vulnerability", "revoke_credential"];

export const DEFAULT_SIMULATION_SETTINGS: SimulationSettings = {
  objective: "mission_then_blast_radius",
  monte_carlo_trials: 1000,
  iterations_per_run: 1000,
  max_attempts: 1,
  rules: DEFAULT_RULES,
};

export function requiresScoring(
  strategy: OptimizationParams["strategy"],
): boolean {
  return (
    strategy === "simulation_informed" || strategy === "simulated_annealing"
  );
}

// The typed request carries scoring settings only for a scoring strategy and
// omits an empty foothold.
export function optimizationRequestParams(
  params: DashboardOptimizationParams,
): OptimizationParams {
  const request: OptimizationParams = {
    strategy: params.strategy,
    budget: params.budget,
    seed: params.seed,
    candidate_action_types: params.candidate_action_types,
    require_pre_attack_feasibility: params.require_pre_attack_feasibility,
    initial_foothold_node_id: params.initial_foothold_node_id || undefined,
  };

  return requiresScoring(params.strategy)
    ? { ...request, simulation_params: params.simulation_params }
    : request;
}
