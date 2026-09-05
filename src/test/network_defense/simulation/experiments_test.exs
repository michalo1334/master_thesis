defmodule NetworkDefense.Simulation.ExperimentsTest do
  use NetworkDefense.DataCase, async: true

  import Ecto.Query

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

    assert {:ok, %{status: :completed, runtime_ms: 7}} =
             Experiments.complete_with_runs(experiment, [run.(1), run.(2)], 7)
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

  test "starts empty running and failed experiments, but leaves terminal experiments unchanged" do
    assert {:ok, graph} = Graphs.insert(Graph.new("Lifecycle graph"))
    running = create_experiment(graph, status: :running)
    failed = create_experiment(graph, status: :failed)
    completed = create_experiment(graph, status: :completed, completed_trials: 2)
    cancelled = create_experiment(graph, status: :cancelled)

    assert {:ok, %{status: :running}} = Experiments.start_empty(running.id)
    assert {:ok, %{status: :running}} = Experiments.start_empty(failed.id)
    assert {:ok, %{status: :completed}} = Experiments.start_empty(completed.id)
    assert {:ok, %{status: :cancelled}} = Experiments.start_empty(cancelled.id)
  end

  test "rejects partial experiments" do
    assert {:ok, graph} = Graphs.insert(Graph.new("Partial graph"))
    experiment = create_experiment(graph)

    experiment
    |> Experiment.changeset(%{completed_trials: 1})
    |> Repo.update!()

    assert {:error, :partial_experiment_unsupported} = Experiments.start_empty(experiment.id)
  end

  test "atomically persists all runs and completes an experiment" do
    assert {:ok, graph} = Graphs.insert(Graph.new("Complete graph"))
    experiment = create_experiment(graph)
    runs = [run(graph, experiment, 1), run(graph, experiment, 2)]

    assert {:ok, %{status: :completed, completed_trials: 2, runtime_ms: 9}} =
             Experiments.complete_with_runs(experiment, runs, 9)

    assert 2 == run_count(experiment)
  end

  test "rejects a mismatched run count" do
    assert {:ok, graph} = Graphs.insert(Graph.new("Count graph"))
    experiment = create_experiment(graph)

    assert {:error, :incomplete} =
             Experiments.complete_with_runs(experiment, [run(graph, experiment, 1)], 5)

    assert 0 == run_count(experiment)
  end

  test "rolls back runs when final insertion fails" do
    assert {:ok, experiment_graph} = Graphs.insert(Graph.new("Experiment rollback graph"))
    experiment = create_experiment(experiment_graph)

    assert {:error, :run} =
             Experiments.complete_with_runs(
               experiment,
               [run(experiment_graph, experiment, 1), run(experiment_graph, experiment, 1)],
               5
             )

    assert 0 == run_count(experiment)
    assert %{status: :running, completed_trials: 0} = Repo.get!(Experiment, experiment.id)
  end

  defp create_experiment(graph, opts \\ []) do
    Experiment.new(
      graph: graph,
      master_seed: 17,
      iteration_count: 1,
      max_attempts: 1,
      total_trials: 2,
      completed_trials: Keyword.get(opts, :completed_trials, 0),
      status: Keyword.get(opts, :status, :running)
    )
    |> Experiments.create()
    |> elem(1)
  end

  defp run(graph, experiment, trial_index) do
    Run.new(
      graph: graph,
      experiment_id: experiment.id,
      trial_index: trial_index,
      seed: trial_index,
      initial_attacker_state: AttackerState.new("host")
    )
  end

  defp run_count(experiment) do
    Run
    |> where([run], run.experiment_id == ^experiment.id)
    |> Repo.aggregate(:count)
  end
end
