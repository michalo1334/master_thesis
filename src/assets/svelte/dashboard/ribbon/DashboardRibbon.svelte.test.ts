import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import DashboardRibbon from "./DashboardRibbon.svelte";
import { defaultForceParams } from "../graph/layout/ForceLayout.types";
import type { OptimizationParams, SimulationParams } from "../contract";

vi.stubGlobal(
  "ResizeObserver",
  class {
    observe() {}
    unobserve() {}
    disconnect() {}
  },
);

type OptimizationOption = {
  id: OptimizationParams["strategy"];
  title: string;
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
  { id: "cvss", title: "CVSS" },
  { id: "simulation_informed", title: "Simulation-informed" },
  { id: "topology_segmentation", title: "Topology segmentation" },
  { id: "simulated_annealing", title: "Simulated annealing" },
];

afterEach(cleanup);

function renderRibbon({
  activeOptimizationId = "simulation_informed",
  footholdHosts = [{ id: "host-1", name: "Host 1" }],
  hasActiveGraph = true,
}: {
  activeOptimizationId?: OptimizationParams["strategy"];
  footholdHosts?: readonly { id: string; name: string }[];
  hasActiveGraph?: boolean;
} = {}) {
  const onOptimize = vi.fn();
  const onOptimizationParamsChange = vi.fn();
  const onCompareGraphs = vi.fn();
  const onOpenAnalysis = vi.fn();

  render(DashboardRibbon, {
    props: {
      hasActiveGraph,
      forceParams: defaultForceParams,
      onForceParamsChange: vi.fn(),
      onForceLayout: vi.fn(),
      onRunSimulation: vi.fn(),
      onCompareGraphs,
      onOpenAnalysis,
      onOptimize,
      optimizationOptions,
      activeOptimizationId,
      optimizationParams: {
        budget: 1,
        strategy: activeOptimizationId,
        objective: "blast_radius",
        simulation_params: simulationParams,
      },
      onOptimizationParamsChange,
      onSimulationParamsChange: vi.fn(),
      simulationParams,
      footholdHosts,
    },
  });

  return {
    onCompareGraphs,
    onOpenAnalysis,
    onOptimize,
    onOptimizationParamsChange,
  };
}

async function openOptimizationTab(): Promise<void> {
  await fireEvent.click(screen.getByRole("tab", { name: "Optimization" }));
}

describe("DashboardRibbon", () => {
  it("starts graph comparison from the Home tab", async () => {
    const { onCompareGraphs } = renderRibbon();

    await fireEvent.click(
      screen.getByRole("button", { name: "Compare graphs" }),
    );

    expect(onCompareGraphs).toHaveBeenCalledOnce();
  });

  it("opens analysis from the Home tab", async () => {
    const { onOpenAnalysis } = renderRibbon();

    await fireEvent.click(screen.getByRole("button", { name: "Analysis" }));

    expect(onOpenAnalysis).toHaveBeenCalledOnce();
  });

  it("shows Strategy and Optimize in the Optimization tab", async () => {
    renderRibbon();
    await openOptimizationTab();

    expect(
      screen.getByRole("combobox", { name: "Strategy" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("spinbutton", { name: "Budget" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Optimize" }),
    ).toBeInTheDocument();
  });

  it("changes the strategy without optimizing", async () => {
    const { onOptimize, onOptimizationParamsChange } = renderRibbon({
      activeOptimizationId: "cvss",
    });
    await openOptimizationTab();

    await fireEvent.change(screen.getByRole("combobox", { name: "Strategy" }), {
      target: { value: "simulation_informed" },
    });

    expect(onOptimizationParamsChange).toHaveBeenCalledWith({
      strategy: "simulation_informed",
    });
    expect(onOptimize).not.toHaveBeenCalled();
  });

  it("optimizes with the selected strategy", async () => {
    const { onOptimize } = renderRibbon({
      activeOptimizationId: "simulated_annealing",
    });
    await openOptimizationTab();

    await fireEvent.click(screen.getByRole("button", { name: "Optimize" }));

    expect(onOptimize).toHaveBeenCalledWith("simulated_annealing");
  });

  it.each(["simulation_informed", "simulated_annealing"] as const)(
    "shows simulation settings for %s",
    async (strategy) => {
      renderRibbon({ activeOptimizationId: strategy });
      await openOptimizationTab();

      expect(screen.getByText("Simulation settings")).toBeInTheDocument();
      expect(
        screen.getByRole("combobox", { name: "Initial foothold" }),
      ).toBeInTheDocument();
      expect(
        screen.getByRole("spinbutton", { name: "Monte Carlo trials" }),
      ).toBeInTheDocument();
      expect(
        screen.getByRole("spinbutton", { name: "Maximum attempts" }),
      ).toBeInTheDocument();
      expect(
        screen.getByRole("combobox", { name: "Objective" }),
      ).toBeInTheDocument();
    },
  );

  it("shows only the foothold setting for topology segmentation", async () => {
    renderRibbon({ activeOptimizationId: "topology_segmentation" });
    await openOptimizationTab();

    expect(
      screen.getByText("Topology segmentation", {
        selector: ".dashboard-ribbon-group-label",
      }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("combobox", { name: "Initial foothold" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("spinbutton", { name: "Monte Carlo trials" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("spinbutton", { name: "Maximum attempts" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("combobox", { name: "Objective" }),
    ).not.toBeInTheDocument();
  });

  it("shows no strategy-specific settings for CVSS", async () => {
    renderRibbon({ activeOptimizationId: "cvss" });
    await openOptimizationTab();

    expect(screen.queryByText("Simulation settings")).not.toBeInTheDocument();
    expect(
      screen.queryByText("Topology segmentation", {
        selector: ".dashboard-ribbon-group-label",
      }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("combobox", { name: "Initial foothold" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("combobox", { name: "Objective" }),
    ).not.toBeInTheDocument();
  });

  it("updates the optimization objective", async () => {
    const { onOptimizationParamsChange } = renderRibbon();
    await openOptimizationTab();

    await fireEvent.change(
      screen.getByRole("combobox", { name: "Objective" }),
      {
        target: { value: "mission_impact" },
      },
    );

    expect(onOptimizationParamsChange).toHaveBeenCalledWith({
      objective: "mission_impact",
    });
  });

  it("keeps non-CVSS optimization disabled without a foothold", async () => {
    const { onOptimize } = renderRibbon({
      activeOptimizationId: "simulation_informed",
      footholdHosts: [],
    });
    await openOptimizationTab();

    expect(screen.getByRole("button", { name: "Optimize" })).toBeDisabled();
    expect(
      screen.getByRole("option", { name: "Simulation-informed" }),
    ).toBeDisabled();
    expect(onOptimize).not.toHaveBeenCalled();
  });

  it("keeps CVSS optimization enabled without a foothold", async () => {
    const { onOptimize } = renderRibbon({
      activeOptimizationId: "cvss",
      footholdHosts: [],
    });
    await openOptimizationTab();

    expect(screen.getByRole("button", { name: "Optimize" })).toBeEnabled();
    await fireEvent.click(screen.getByRole("button", { name: "Optimize" }));
    expect(onOptimize).toHaveBeenCalledWith("cvss");
  });

  it("keeps the standalone simulation controls unchanged", async () => {
    renderRibbon({ footholdHosts: [] });

    expect(screen.getByRole("tab", { name: "Simulation" })).toBeInTheDocument();
    expect(
      screen.getByRole("tab", { name: "Optimization" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("tab", { name: "Analyze" }),
    ).not.toBeInTheDocument();

    await fireEvent.click(screen.getByRole("tab", { name: "Simulation" }));

    expect(
      screen.getByRole("button", { name: "Simulate" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("spinbutton", { name: "Seed" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Optimize" }),
    ).not.toBeInTheDocument();
  });
});
