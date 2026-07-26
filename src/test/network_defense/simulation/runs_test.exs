defmodule NetworkDefense.Simulation.RunsTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Actions.ExploitVulnerability
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.Runs
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Simulation.Types.AttackerState, as: AttackerStateType

  test "persists and reloads a simulation with its iteration steps" do
    graph = insert_graph()
    attacker_state = AttackerState.new("source-host")
    action = exploit_action()
    seed = :rand.seed_s(:exsss, {1, 2, 3})
    edge_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

    run =
      Run.new(
        graph: graph,
        initial_seed: 42,
        initial_attacker_state: attacker_state,
        iteration_count: 1,
        iterations: [
          IterationStep.new(
            index: 1,
            attempted_action: action,
            success?: true,
            successful_edge_ids: edge_ids,
            attacker_state: AttackerState.mark_attempted(attacker_state, action),
            seed: seed
          )
        ]
      )

    assert {:ok, persisted} = Runs.insert(run)

    loaded = Runs.load(persisted.id)

    assert loaded.graph_id == graph.id
    assert loaded.initial_seed == 42
    assert loaded.initial_attacker_state == attacker_state
    assert [step] = loaded.iterations
    assert step.index == 1
    assert step.attempted_action == action
    assert step.success?
    assert step.successful_edge_ids == edge_ids
    assert step.seed == seed
    assert Run.current_attacker_state(loaded) == step.attacker_state
    assert Run.current_seed(loaded) == seed
    refute AttackerState.attempted?(step.attacker_state, action)
  end

  test "does not persist attempted actions" do
    action = exploit_action()

    state =
      AttackerState.new("source-host")
      |> AttackerState.mark_attempted(action)

    assert {:ok, snapshot} = AttackerStateType.dump(state)
    refute Map.has_key?(snapshot, "attempted_actions")
    assert {:ok, restored} = AttackerStateType.load(snapshot)
    refute AttackerState.attempted?(restored, action)
  end

  test "reports an invalid experiment association" do
    graph = insert_graph()

    changeset =
      %Run{graph_id: graph.id}
      |> Run.changeset(%{
        initial_seed: 1,
        initial_attacker_state: AttackerState.new("source-host"),
        iteration_count: 1,
        experiment_id: Ecto.UUID.generate()
      })

    assert {:error, changeset} = Repo.insert(changeset)
    assert "does not exist" in errors_on(changeset).experiment_id
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
      success_probability: 0.5,
      required_privilege: :none,
      granted_privilege: :user
    }
  end
end
