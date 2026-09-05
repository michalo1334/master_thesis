defmodule NetworkDefense.Compute.SimulationOperation do
  @moduledoc false

  @behaviour NetworkDefense.Compute.ScatterGather

  alias NetworkDefense.Graph.{Graphs, MaterializeReachability}
  alias NetworkDefense.Simulation.{Experiment, Experiments, Simulator}
  alias NetworkDefense.Simulation.Telemetry, as: SimulationTelemetry

  @trial_batch_size 500

  @impl true
  def scatter(%Experiment{completed_trials: completed_trials}) when completed_trials != 0 do
    raise "scatter-gather requires an empty experiment"
  end

  def scatter(%Experiment{} = experiment) do
    1..experiment.total_trials
    |> Stream.chunk_every(@trial_batch_size)
    |> Stream.map(fn trial_indexes ->
      {first_index, last_index} = Enum.min_max(trial_indexes)
      range = first_index..last_index

      {{experiment.id, first_index, last_index}, length(trial_indexes),
       %{experiment_id: experiment.id, trial_indexes: range}}
    end)
  end

  @impl true
  def execute(fetch_partition) do
    %{experiment_id: experiment_id, trial_indexes: trial_indexes} = fetch_partition.()
    experiment = Experiments.get(experiment_id)

    graph =
      experiment.graph_revision_id
      |> Graphs.load_revision!()
      |> MaterializeReachability.materialize()

    initial_attacker_state =
      Simulator.initial_attacker_state(graph, experiment.initial_foothold_node_id)

    SimulationTelemetry.compute(experiment, trial_indexes, fn ->
      :timer.tc(fn ->
        Simulator.run_batch(experiment, graph, initial_attacker_state, trial_indexes,
          rules: Simulator.default_rules(),
          max_attempts: experiment.max_attempts
        )
      end)
    end)
    |> then(fn {_elapsed_us, runs} -> {:ok, runs} end)
  end

  @impl true
  def gather(results, experiment, %{compute_duration_ms: runtime_ms}) do
    results
    |> Enum.flat_map(fn {_key, runs} -> runs end)
    |> then(&Experiments.complete_with_runs(experiment, &1, runtime_ms))
  end
end
