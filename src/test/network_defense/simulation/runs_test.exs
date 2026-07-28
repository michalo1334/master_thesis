defmodule NetworkDefense.Simulation.RunsTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Actions.AttemptedAction
  alias NetworkDefense.Actions.ExploitVulnerability
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.Runs
  alias NetworkDefense.Simulation.Run

  test "persists and reloads a simulation with its iteration steps" do
    graph = insert_graph()
    attacker_state = AttackerState.new("source-host")
    action = exploit_action()
    attempted_action = AttemptedAction.new(action)

    run =
      Run.new(
        graph: graph,
        seed: 42,
        initial_attacker_state: attacker_state,
        iterations: [
          IterationStep.new(
            index: 1,
            attempted_action: attempted_action,
            success?: true,
            attacker_state: AttackerState.mark_attempted(attacker_state, action, 1)
          )
        ]
      )

    assert {:ok, persisted} = Runs.insert(run)

    loaded = Runs.load(persisted.id)

    assert loaded.graph_id == graph.id
    assert loaded.seed == 42
    assert loaded.initial_attacker_state == attacker_state
    assert [step] = loaded.iterations
    assert step.index == 1
    assert AttemptedAction.action(step.attempted_action) == action
    assert step.attempted_action.attempt_count == attempted_action.attempt_count
    assert step.success?
    assert Run.current_attacker_state(loaded) == step.attacker_state
    assert AttackerState.attempted?(step.attacker_state, action)
  end

  test "reports an invalid experiment association" do
    graph = insert_graph()

    changeset =
      %Run{graph_id: graph.id}
      |> Run.changeset(%{
        seed: 1,
        initial_attacker_state: AttackerState.new("source-host"),
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
      source_host_id: "source-host",
      target_host_id: "target-host",
      service_id: "service",
      vulnerability_node_id: "vulnerability",
      success_probability: 0.5,
      required_privilege: :none,
      granted_privilege: :user,
      supporting_edge_ids: []
    }
  end
end
