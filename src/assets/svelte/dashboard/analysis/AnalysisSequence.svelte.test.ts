import { describe, expect, it, vi } from "vitest";
import { waitFor } from "@testing-library/svelte";
import { AnalysisSequence } from "./AnalysisSequence.svelte";
import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import type {
  LoadedGraph,
  OptimizationParams,
  SimulationParams,
} from "../contract";

function graph(revisionId: string): LoadedGraph {
  return {
    id: "graph-1",
    title: "Topology",
    revision_id: revisionId,
    parent_revision_id: null,
    revision_kind: "original",
    revision_number: 1,
    nodes: [],
    edges: [],
  };
}

function document(revisionId: string): EditableGraphDocument {
  const document = new EditableGraphDocument();
  document.replaceFromLoadedGraph(graph(revisionId));
  return document;
}

const simulationParams: SimulationParams = {
  initial_foothold_node_id: "host-1",
  monte_carlo_trials: 1000,
  iterations_per_run: 1000,
  max_attempts: 1,
  generate_seed: false,
  seed: 1,
};

const optimizationParams: OptimizationParams = {
  strategy: "cvss",
  budget: 1,
  objective: "blast_radius",
  simulation_params: simulationParams,
};

describe("AnalysisSequence", () => {
  it("starts each job only after the prior completion event", async () => {
    const source = document("source-r1");
    const optimized = document("optimized-r1");
    const startSimulation = vi
      .fn()
      .mockResolvedValueOnce(true)
      .mockResolvedValueOnce(true);
    const startOptimization = vi.fn().mockResolvedValue(true);
    const loadOutputGraph = vi.fn().mockResolvedValue(optimized);
    const sequence = new AnalysisSequence({
      startSimulation,
      startOptimization,
      loadOutputGraph,
    });

    await expect(
      sequence.start(source, simulationParams, optimizationParams),
    ).resolves.toBe(true);
    expect(startSimulation).toHaveBeenCalledOnce();
    expect(startOptimization).not.toHaveBeenCalled();

    sequence.onSimulationCompleted({
      correlation_id: sequence.baselineSimulationCorrelationId!,
      graph_id: "graph-1",
      graph_revision_id: "source-r1",
      experiment_id: "baseline-experiment",
    });
    await waitFor(() => expect(startOptimization).toHaveBeenCalledOnce());
    expect(startSimulation).toHaveBeenCalledOnce();

    sequence.onOptimizationCompleted({
      correlation_id: sequence.optimizationCorrelationId!,
      graph_id: "graph-1",
      graph_revision_id: "source-r1",
      optimization_id: "optimization-1",
      output_graph_revision_id: "optimized-r1",
    });
    await waitFor(() => expect(startSimulation).toHaveBeenCalledTimes(2));
    expect(loadOutputGraph).toHaveBeenCalledWith("optimized-r1");
    expect(startSimulation).toHaveBeenLastCalledWith(
      expect.objectContaining({ loadedRevisionId: "optimized-r1" }),
      simulationParams,
      expect.objectContaining({ graphRevisionId: "optimized-r1" }),
    );

    sequence.onSimulationCompleted({
      correlation_id: sequence.afterSimulationCorrelationId!,
      graph_id: "graph-1",
      graph_revision_id: "optimized-r1",
      experiment_id: "after-experiment",
    });

    expect(sequence.stage).toBe("completed");
    expect(sequence.progress).toEqual({ completed: 3, total: 3 });
  });

  it("ignores unrelated failures and fails on the matching operation", async () => {
    const startSimulation = vi.fn().mockResolvedValue(true);
    const sequence = new AnalysisSequence({
      startSimulation,
      startOptimization: vi.fn(),
      loadOutputGraph: vi.fn(),
    });

    await sequence.start(
      document("source-r1"),
      simulationParams,
      optimizationParams,
    );

    sequence.onSimulationFailed({
      correlation_id: "other",
      graph_id: "graph-1",
      graph_revision_id: "source-r1",
      reason: "ignored",
    });
    expect(sequence.stage).toBe("awaiting-baseline");

    sequence.onSimulationFailed({
      correlation_id: sequence.baselineSimulationCorrelationId!,
      graph_id: "graph-1",
      graph_revision_id: "source-r1",
      reason: "worker_failed",
    });

    expect(sequence.stage).toBe("failed");
    expect(sequence.error).toBe("Baseline simulation failed: worker_failed");
  });

  it("fails when the optimization request is rejected", async () => {
    const sequence = new AnalysisSequence({
      startSimulation: vi.fn().mockResolvedValue(true),
      startOptimization: vi.fn().mockResolvedValue(false),
      loadOutputGraph: vi.fn(),
    });

    await sequence.start(
      document("source-r1"),
      simulationParams,
      optimizationParams,
    );
    sequence.onSimulationCompleted({
      correlation_id: sequence.baselineSimulationCorrelationId!,
      graph_id: "graph-1",
      graph_revision_id: "source-r1",
      experiment_id: "baseline-experiment",
    });

    await waitFor(() => expect(sequence.stage).toBe("failed"));
    expect(sequence.error).toBe("Optimization did not start.");
  });

  it("registers each job before a synchronous completion event", async () => {
    const optimized = document("optimized-r1");
    let sequence: AnalysisSequence;
    const startSimulation = vi.fn(async (_document, _params, job) => {
      sequence.onSimulationCompleted({
        correlation_id: job.correlationId,
        graph_id: job.graphId,
        graph_revision_id: job.graphRevisionId,
        experiment_id: `${job.correlationId}-experiment`,
      });
      return true;
    });
    const startOptimization = vi.fn(async (_document, _params, job) => {
      sequence.onOptimizationCompleted({
        correlation_id: job.correlationId,
        graph_id: job.graphId,
        graph_revision_id: job.graphRevisionId,
        optimization_id: `${job.correlationId}-optimization`,
        output_graph_revision_id: "optimized-r1",
      });
      return true;
    });
    sequence = new AnalysisSequence({
      startSimulation,
      startOptimization,
      loadOutputGraph: vi.fn().mockResolvedValue(optimized),
    });

    await expect(
      sequence.start(
        document("source-r1"),
        simulationParams,
        optimizationParams,
      ),
    ).resolves.toBe(true);

    await waitFor(() => expect(sequence.stage).toBe("completed"));
    expect(startSimulation).toHaveBeenCalledTimes(2);
    expect(startOptimization).toHaveBeenCalledOnce();
  });

  it("handles a synchronous baseline failure", async () => {
    let sequence: AnalysisSequence;
    sequence = new AnalysisSequence({
      startSimulation: vi.fn(async (_document, _params, job) => {
        sequence.onSimulationFailed({
          correlation_id: job.correlationId,
          graph_id: job.graphId,
          graph_revision_id: job.graphRevisionId,
          reason: "worker_failed",
        });
        return true;
      }),
      startOptimization: vi.fn(),
      loadOutputGraph: vi.fn(),
    });

    await expect(
      sequence.start(
        document("source-r1"),
        simulationParams,
        optimizationParams,
      ),
    ).resolves.toBe(false);
    expect(sequence.stage).toBe("failed");
    expect(sequence.error).toBe("Baseline simulation failed: worker_failed");
  });
});
