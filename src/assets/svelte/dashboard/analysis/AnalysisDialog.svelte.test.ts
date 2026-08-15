import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/svelte";
import AnalysisDialog from "./AnalysisDialog.svelte";
import type { AnalysisModel } from "./AnalysisModel.svelte";

afterEach(cleanup);

function renderDialog({
  includeOptimization = false,
  selectedStrategies = [],
  dialogStatusMessage = "",
}: {
  includeOptimization?: boolean;
  selectedStrategies?: string[];
  dialogStatusMessage?: string;
} = {}) {
  const openTargetPicker = vi.fn();
  const run = vi.fn().mockResolvedValue(true);
  const closeDialog = vi.fn();
  const model = {
    open: true,
    targetRevisionId: "",
    targetGraph: undefined,
    targetLabel: "Choose graph",
    includeSimulation: true,
    includeOptimization,
    selectedStrategies,
    isLoadingTarget: false,
    isRunning: false,
    statusMessage: "",
    dialogStatusMessage,
    targetFootholdHosts: [],
    runnableStrategies: selectedStrategies,
    needsSimulationSettings: false,
    needsFoothold: false,
    canRun: true,
    workspace: {
      graphSummaries: [
        {
          graph_id: "graph-1",
          revision_id: "revision-1",
          title: "Graph 1",
          node_count: 1,
          edge_count: 0,
          parent_revision_id: null,
          revision_kind: "original",
          revision_number: 1,
          is_favorite: false,
        },
      ],
      simulationParams: {
        initial_foothold_node_id: "",
        monte_carlo_trials: 1000,
        iterations_per_run: 1000,
        max_attempts: 1,
        generate_seed: false,
        seed: 0,
      },
      optimizationParams: {
        budget: 1,
        strategy: "cvss",
        objective: "blast_radius",
        simulation_params: {
          initial_foothold_node_id: "",
          monte_carlo_trials: 1000,
          iterations_per_run: 1000,
          max_attempts: 1,
          generate_seed: false,
          seed: 0,
        },
      },
      onSimulationParamsChange: vi.fn(),
      onOptimizationParamsChange: vi.fn(),
    },
    openDialog: vi.fn(),
    closeDialog,
    openTargetPicker,
    setStrategies: vi.fn(),
    run,
  } as unknown as AnalysisModel;

  render(AnalysisDialog, {
    props: {
      model,
      optimizationOptions: [
        { id: "cvss", title: "CVSS" },
        { id: "simulation_informed", title: "Simulation-informed" },
        { id: "topology_segmentation", title: "Topology segmentation" },
        { id: "simulated_annealing", title: "Simulated annealing" },
      ],
    },
  });

  return {
    closeDialog,
    onOptimizationParamsChange: model.workspace.onOptimizationParamsChange,
    openTargetPicker,
    run,
  };
}

describe("AnalysisDialog", () => {
  it("opens the target graph picker and runs the configured analysis", async () => {
    const { openTargetPicker, run } = renderDialog();

    await fireEvent.click(
      screen.getByRole("button", {
        name: "Select target graph: Choose graph",
      }),
    );
    await fireEvent.click(screen.getByRole("button", { name: "Run analysis" }));

    expect(openTargetPicker).toHaveBeenCalledOnce();
    await waitFor(() => expect(run).toHaveBeenCalledOnce());
  });

  it("closes through the model", async () => {
    const { closeDialog } = renderDialog();

    await fireEvent.click(screen.getByRole("button", { name: "Cancel" }));

    expect(closeDialog).toHaveBeenCalledOnce();
  });

  it("shows and updates the objective for mission-aware strategies", async () => {
    const { onOptimizationParamsChange } = renderDialog({
      includeOptimization: true,
      selectedStrategies: ["simulation_informed"],
    });

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

  it("shows compound strategy validation", () => {
    renderDialog({
      includeOptimization: true,
      selectedStrategies: ["cvss", "simulation_informed"],
      dialogStatusMessage:
        "Select exactly one runnable optimization strategy for the combined workflow.",
    });

    expect(
      screen.getByText(
        "Select exactly one runnable optimization strategy for the combined workflow.",
      ),
    ).toBeInTheDocument();
  });
});
