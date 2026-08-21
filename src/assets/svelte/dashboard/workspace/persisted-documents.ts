import type { OptimizationParams, SimulationParams } from "../contract";
import type { ForceParams } from "../graph/layout/ForceLayout.types";

export interface DashboardWorkspaceState {
  forceParams: ForceParams;
  simulationParams: SimulationParams;
  optimizationParams: OptimizationParams;
}

export function isDashboardWorkspaceState(
  value: unknown,
): value is DashboardWorkspaceState {
  if (!isRecord(value)) return false;
  return (
    isForceParams(value.forceParams) &&
    isSimulationParams(value.simulationParams) &&
    isOptimizationParams(value.optimizationParams)
  );
}

function isForceParams(value: unknown): value is ForceParams {
  return (
    isRecord(value) &&
    isNumber(value.repulsion) &&
    isNumber(value.linkDistance) &&
    isNumber(value.collisionRadius) &&
    isNumber(value.centerStrength) &&
    isNumber(value.alphaDecay)
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
