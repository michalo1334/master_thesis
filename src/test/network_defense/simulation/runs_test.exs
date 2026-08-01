defmodule NetworkDefense.Simulation.RunsTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Simulation.{IterationStep, Run, Runs}

  test "persists a run pinned to a graph revision" do
    assert {:ok, graph} = Graphs.insert(Graph.new("Simulation graph"))
    attacker_state = AttackerState.new("source-host")

    run =
      Run.new(
        graph: graph,
        seed: 42,
        initial_attacker_state: attacker_state,
        iterations: [IterationStep.new(index: 1, success?: false, attacker_state: attacker_state)]
      )

    assert {:ok, persisted} = Runs.insert(run)
    assert %{graph_revision_id: revision_id, iterations: [%{index: 1}]} = Runs.load(persisted.id)
    assert revision_id == graph.revision_id
  end
end
