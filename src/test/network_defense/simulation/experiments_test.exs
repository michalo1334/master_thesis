defmodule NetworkDefense.Simulation.ExperimentsTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Actions.AttemptedAction
  alias NetworkDefense.Actions.ExploitVulnerability
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.Run

  test "streams large iteration inserts in bounded batches" do
    graph = insert_graph()
    attacker_state = AttackerState.new("source-host")

    action =
      %ExploitVulnerability{
        source_host_id: "source",
        supporting_edge_ids: []
      }

    attempted_action = AttemptedAction.new(action)

    run =
      Run.new(
        graph: graph,
        seed: 42,
        initial_attacker_state: attacker_state,
        iterations:
          Enum.map(1..10_000, fn index ->
            IterationStep.new(
              index: index,
              success?: true,
              attempted_action: attempted_action,
              attacker_state: attacker_state
            )
          end)
      )

    experiment =
      Experiment.new(
        graph: graph,
        master_seed: 42,
        iteration_count: 10_000,
        max_attempts: 1,
        runs: [run]
      )

    assert {:ok, _experiment} = Experiments.insert(experiment)
    assert Repo.aggregate(IterationStep, :count) == 10_000
  end

  test "persists committed batches and resumes a failed experiment" do
    graph = insert_graph()
    attacker_state = AttackerState.new("source-host")

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

    assert {:ok, experiment} =
             Experiments.append_batch(experiment, [run(graph, experiment, 1, attacker_state)], 3)

    assert %{completed_trials: 1, runtime_ms: 3, status: "running"} = experiment

    assert {:ok, %{status: "failed"}} = Experiments.fail(experiment.id)
    assert {:ok, experiment} = Experiments.resume(experiment.id)

    assert {:ok, experiment} =
             Experiments.append_batch(experiment, [run(graph, experiment, 2, attacker_state)], 4)

    assert {:ok, %{status: "completed", completed_trials: 2, runtime_ms: 7}} =
             Experiments.complete(experiment)

    assert Repo.aggregate(Run, :count) == 2
  end

  defp insert_graph do
    %Graph{id: Ecto.UUID.generate()}
    |> Graph.changeset(%{title: "Simulation graph"})
    |> Repo.insert!()
  end

  defp run(graph, experiment, trial_index, attacker_state) do
    Run.new(
      graph: graph,
      experiment_id: experiment.id,
      trial_index: trial_index,
      seed: trial_index,
      initial_attacker_state: attacker_state
    )
  end
end
