import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import DashboardRibbon from "./DashboardRibbon.svelte";
import { defaultForceParams } from "../graph/layout/ForceLayout.types";
import type { OptimizationParams, SimulationParams } from "../contract";
import type { SplitButtonOption } from "../ui/SplitButton.svelte";

vi.stubGlobal(
  "ResizeObserver",
  class {
    observe() {}
    unobserve() {}
    disconnect() {}
  },
);

type OptimizationOption = SplitButtonOption & {
  id: OptimizationParams["strategy"];
};

const simulationParams: SimulationParams = {
  generate_seed: false,
  initial_foothold_node_id: "host-1",
  iterations_per_run: 1000,
  max_attempts: 1,
  monte_carlo_trials: 1000,
  seed: 1,
};

const optimizationOptions: OptimizationOption[] = [
  { id: "cvss", icon: "shield", title: "CVSS" },
  {
    id: "simulation_informed",
    icon: "graph",
    title: "Simulation-informed",
  },
  {
    id: "topology_segmentation",
    icon: "graph",
    title: "Topology segmentation",
  },
  {
    id: "simulated_annealing",
    icon: "shield",
    title: "Simulated annealing",
  },
];

afterEach(cleanup);

describe("DashboardRibbon", () => {
  it("limits optimization to CVSS when no foothold host is available", async () => {
    render(DashboardRibbon, {
      props: {
        hasActiveGraph: true,
        hasUnreadReport: false,
        isLoadingExperiments: false,
        forceParams: defaultForceParams,
        onForceParamsChange: vi.fn(),
        onForceLayout: vi.fn(),
        onRunSimulation: vi.fn(),
        onShowExperiments: vi.fn(),
        onOptimize: vi.fn(),
        optimizationOptions,
        activeOptimizationId: "simulation_informed",
        optimizationParams: {
          budget: 1,
          strategy: "simulation_informed",
          simulation_params: simulationParams,
        },
        onOptimizationParamsChange: vi.fn(),
        onSimulationParamsChange: vi.fn(),
        simulationParams,
        footholdHosts: [],
      },
    });

    await fireEvent.click(screen.getByRole("tab", { name: "Analyze" }));

    expect(screen.getByRole("button", { name: "Optimize" })).toHaveAttribute(
      "title",
      "Simulation-informed",
    );
    expect(screen.getByRole("button", { name: "Optimize" })).toBeDisabled();

    await fireEvent.click(screen.getByRole("button", { name: "More options" }));

    expect(
      await screen.findByRole("menuitem", { name: /CVSS/ }),
    ).not.toHaveAttribute("data-disabled");
    for (const name of [
      /Simulation-informed/,
      /Topology segmentation/,
      /Simulated annealing/,
    ]) {
      expect(screen.getByRole("menuitem", { name })).toHaveAttribute(
        "data-disabled",
      );
    }
  });
});
