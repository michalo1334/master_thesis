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

  test "splits large iteration inserts below PostgreSQL's bind limit" do
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

  defp insert_graph do
    %Graph{id: Ecto.UUID.generate()}
    |> Graph.changeset(%{title: "Simulation graph"})
    |> Repo.insert!()
  end
end
