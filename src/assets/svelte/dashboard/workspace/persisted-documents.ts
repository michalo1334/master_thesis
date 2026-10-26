import type { OptimizationParams } from "../../contracts.generated/optimization";
import type { SimulationParams } from "../../contracts.generated/simulation";
import type { DashboardOptimizationParams } from "../contract";
import {
  DEFAULT_CANDIDATE_ACTION_TYPES,
  DEFAULT_RULES,
  DEFAULT_SIMULATION_SETTINGS,
} from "../contract";

export interface DashboardWorkspaceState {
  simulationParams: SimulationParams;
  optimizationParams: DashboardOptimizationParams;
}

interface LegacyOptimizationParams {
  strategy: OptimizationParams["strategy"];
  seed: number;
  budget: number;
  simulation_params: {
    initial_foothold_node_id: string;
    monte_carlo_trials: number;
    iterations_per_run: number;
    max_attempts: number;
    generate_seed: boolean;
    seed: number;
  };
}

interface LegacyDashboardWorkspaceState {
  simulationParams: Omit<
    SimulationParams,
    "rules" | "require_pre_attack_feasibility"
  >;
  optimizationParams: LegacyOptimizationParams;
}

export function isDashboardWorkspaceState(
  value: unknown,
): value is DashboardWorkspaceState {
  return isCurrentState(value) || isLegacyState(value);
}

export function upgradeDashboardWorkspaceState(
  value: DashboardWorkspaceState,
): DashboardWorkspaceState {
  return isCurrentState(value) ? value : upgradeLegacyState(value as never);
}

function upgradeLegacyState(
  value: LegacyDashboardWorkspaceState,
): DashboardWorkspaceState {
  const previousOptimization = value.optimizationParams;
  const previousSimulation = previousOptimization.simulation_params;

  return {
    simulationParams: {
      ...value.simulationParams,
      rules: DEFAULT_RULES,
      require_pre_attack_feasibility: true,
    },
    optimizationParams: {
      strategy: previousOptimization.strategy,
      budget: previousOptimization.budget,
      seed: previousOptimization.seed ?? previousSimulation.seed,
      candidate_action_types: DEFAULT_CANDIDATE_ACTION_TYPES,
      require_pre_attack_feasibility: true,
      initial_foothold_node_id: previousSimulation.initial_foothold_node_id,
      generate_seed: previousSimulation.generate_seed,
      simulation_params: {
        ...DEFAULT_SIMULATION_SETTINGS,
        monte_carlo_trials: previousSimulation.monte_carlo_trials,
        iterations_per_run: previousSimulation.iterations_per_run,
        max_attempts: previousSimulation.max_attempts,
      },
    },
  };
}

function isCurrentState(value: unknown): value is DashboardWorkspaceState {
  return (
    isRecord(value) &&
    isSimulationParams(value.simulationParams) &&
    isOptimizationParams(value.optimizationParams)
  );
}

function isLegacyState(value: unknown): value is LegacyDashboardWorkspaceState {
  if (!isRecord(value)) return false;
  const optimization = value.optimizationParams;

  return (
    isSimulationParams(value.simulationParams) &&
    isRecord(optimization) &&
    isStrategy(optimization.strategy) &&
    isNumber(optimization.budget) &&
    isRecord(optimization.simulation_params) &&
    typeof optimization.simulation_params.initial_foothold_node_id ===
      "string" &&
    isNumber(optimization.simulation_params.monte_carlo_trials) &&
    isNumber(optimization.simulation_params.iterations_per_run) &&
    isNumber(optimization.simulation_params.max_attempts) &&
    typeof optimization.simulation_params.generate_seed === "boolean"
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

function isSimulationSettings(value: unknown): boolean {
  return (
    isRecord(value) &&
    typeof value.objective === "string" &&
    isNumber(value.monte_carlo_trials) &&
    isNumber(value.iterations_per_run) &&
    isNumber(value.max_attempts) &&
    isRules(value.rules)
  );
}

function isOptimizationParams(
  value: unknown,
): value is DashboardOptimizationParams {
  return (
    isRecord(value) &&
    isStrategy(value.strategy) &&
    isNumber(value.budget) &&
    isNumber(value.seed) &&
    isRules(value.candidate_action_types) &&
    typeof value.require_pre_attack_feasibility === "boolean" &&
    typeof value.generate_seed === "boolean" &&
    (value.initial_foothold_node_id == null ||
      typeof value.initial_foothold_node_id === "string") &&
    isSimulationSettings(value.simulation_params)
  );
}

function isRules(value: unknown): value is string[] {
  return (
    Array.isArray(value) && value.every((rule) => typeof rule === "string")
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
