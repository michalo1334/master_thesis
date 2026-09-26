import type { OptimizationParams } from "../../contracts.generated/optimization";
import type { SimulationParams } from "../../contracts.generated/simulation";

export interface DashboardWorkspaceState {
  simulationParams: SimulationParams;
  optimizationParams: OptimizationParams;
}

export function isDashboardWorkspaceState(
  value: unknown,
): value is DashboardWorkspaceState {
  if (!isRecord(value)) return false;
  return (
    isSimulationParams(value.simulationParams) &&
    isOptimizationParams(value.optimizationParams)
  );
}

function isSimulationParams(value: unknown): value is SimulationParams {
  return (
    isRecord(value) &&
    typeof value.initial_foothold_node_id === "string" &&
    isNumber(value.monte_carlo_trials) &&
    isNumber(value.iterations_per_run) &&
    isNumber(value.max_attempts) &&
    typeof value.generate_seed === "boolean" &&
    isNumber(value.seed)
  );
}

function isOptimizationParams(value: unknown): value is OptimizationParams {
  return (
    isRecord(value) &&
    isStrategy(value.strategy) &&
    isNumber(value.budget) &&
    isSimulationParams(value.simulation_params)
  );
}

function isStrategy(value: unknown): value is OptimizationParams["strategy"] {
  return [
    "cvss",
    "simulation_informed",
    "topology_segmentation",
    "simulated_annealing",
  ].includes(value as string);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}
