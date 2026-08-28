import type { OptimizationParams } from "../contracts.generated/optimization";
import type { SimulationParams } from "../contracts.generated/simulation";
export type OptimizationParamsChange = Omit<
  Partial<OptimizationParams>,
  "simulation_params"
> & {
  simulation_params?: Partial<SimulationParams>;
};
