defmodule NetworkDefense.Simulation.SimulationsTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Actions.ExploitVulnerability
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.Simulations
  alias NetworkDefense.Simulation.State

  test "persists and reloads a simulation with its iteration steps" do
    graph = insert_graph()
    attacker_state = AttackerState.new("source-host")
    action = exploit_action()
    seed = :rand.seed_s(:exsss, {1, 2, 3})

    state =
      State.new(
        graph: graph,
        initial_seed: 42,
        initial_attacker_state: attacker_state,
        iteration_count: 1,
        iterations: [
          IterationStep.new(
            index: 1,
            attempted_action: action,
            success?: true,
            attacker_state:
              AttackerState.mark_attempted(attacker_state, {"source-host", "vulnerability"}),
            seed: seed
          )
        ]
      )

    assert {:ok, persisted} = Simulations.insert(state)

    loaded = Simulations.load(persisted.id)

    assert loaded.graph_id == graph.id
    assert loaded.initial_seed == 42
    assert loaded.initial_attacker_state == attacker_state
    assert [step] = loaded.iterations
    assert step.index == 1
    assert step.attempted_action == action
    assert step.success?
    assert step.seed == seed
    assert State.current_attacker_state(loaded) == step.attacker_state
    assert State.current_seed(loaded) == seed
  end

  test "encodes attacker state as JSON-safe data" do
    state =
      AttackerState.new("source-host")
      |> AttackerState.mark_attempted({"source-host", "vulnerability"})

    assert %{
             "footholds" => ["source-host"],
             "attempted_actions" => [_]
           } = state |> Jason.encode!() |> Jason.decode!()
  end

  defp insert_graph do
    %Graph{id: Ecto.UUID.generate()}
    |> Graph.changeset(%{title: "Simulation graph"})
    |> Repo.insert!()
  end

  defp exploit_action do
    %ExploitVulnerability{
      source_host: %Node{id: "source-host"},
      target_host: %Node{id: "target-host"},
      service: %Node{id: "service"},
      vulnerability_node: %Node{id: "vulnerability"},
      success_probability: 0.5
    }
  end
end
