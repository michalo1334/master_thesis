defmodule NetworkDefense.Simulation.ExperimentsTest do
  use NetworkDefense.DataCase, async: true

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
    seed = :rand.seed_s(:exsss, {1, 2, 3})

    run =
      Run.new(
        graph: graph,
        initial_seed: 42,
        initial_attacker_state: attacker_state,
        iteration_count: 10_000,
        iterations:
          Enum.map(1..10_000, fn index ->
            IterationStep.new(
              index: index,
              success?: true,
              attacker_state: attacker_state,
              seed: seed
            )
          end)
      )

    experiment =
      Experiment.new(
        graph: graph,
        seed: 42,
        iteration_count: 10_000,
        run_count: 1,
        initial_attacker_state: attacker_state,
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
