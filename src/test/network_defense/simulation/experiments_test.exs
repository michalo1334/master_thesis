defmodule NetworkDefense.Simulation.ExperimentsTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Simulation.{Experiment, Experiments, Run}
  alias NetworkDefense.Repo

  test "persists committed batches for the pinned graph revision" do
    assert {:ok, graph} = Graphs.insert(Graph.new("Topology"))

    experiment =
      Experiment.new(
        graph: graph,
        master_seed: 42,
        iteration_count: 1,
        max_attempts: 1,
        total_trials: 2,
        initial_foothold_node_id: Ecto.UUID.generate()
      )

    assert {:ok, experiment} = Experiments.create(experiment)
    assert experiment.graph_revision_id == graph.revision_id

    run = fn trial_index ->
      Run.new(
        graph: graph,
        experiment_id: experiment.id,
        trial_index: trial_index,
        seed: trial_index,
        initial_attacker_state: AttackerState.new("host")
      )
    end

    assert {:ok, experiment} = Experiments.append_batch(experiment, [run.(1)], 3)
    assert {:ok, experiment} = Experiments.append_batch(experiment, [run.(2)], 4)
    assert {:ok, %{status: "completed", runtime_ms: 7}} = Experiments.complete(experiment)
  end

  test "database rejects a run whose revision differs from its experiment" do
    assert {:ok, experiment_graph} = Graphs.insert(Graph.new("Experiment graph"))
    assert {:ok, run_graph} = Graphs.insert(Graph.new("Run graph"))

    experiment =
      Experiment.new(
        graph: experiment_graph,
        master_seed: 42,
        iteration_count: 1,
        max_attempts: 1,
        total_trials: 1
      )

    assert {:ok, experiment} = Experiments.create(experiment)

    assert {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} =
             Repo.query(
               """
               INSERT INTO simulation_runs
                 (id, graph_revision_id, experiment_id, seed, initial_attacker_state, inserted_at, updated_at)
               VALUES ($1, $2, $3, 0, $4, now(), now())
               """,
               [
                 Ecto.UUID.dump!(Ecto.UUID.generate()),
                 Ecto.UUID.dump!(run_graph.revision_id),
                 Ecto.UUID.dump!(experiment.id),
                 %{"compromised_node_ids" => [], "credentials" => []}
               ]
             )
  end
end
