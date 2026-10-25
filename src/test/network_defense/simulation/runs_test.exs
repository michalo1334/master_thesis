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
        runtime_us: 321,
        initial_attacker_state: attacker_state,
        iterations: [IterationStep.new(index: 1, success?: false, attacker_state: attacker_state)]
      )

    assert {:ok, persisted} = Runs.insert(run)
    assert %{graph_revision_id: revision_id, iterations: [%{index: 1}]} = Runs.load(persisted.id)
    assert revision_id == graph.revision_id
  end

  test "persists the measured trial runtime in microseconds" do
    assert {:ok, graph} = Graphs.insert(Graph.new("Measured runtime graph"))

    run =
      Run.new(
        graph: graph,
        seed: 7,
        runtime_us: 1234,
        initial_attacker_state: AttackerState.new("source-host")
      )

    assert {:ok, persisted} = Runs.insert(run)
    assert %{runtime_us: 1234} = Runs.load(persisted.id)
  end

  test "requires a non-negative trial runtime" do
    attrs = %{
      graph_revision_id: Ecto.UUID.generate(),
      seed: 0,
      trial_index: 0,
      initial_attacker_state: AttackerState.new("source-host")
    }

    assert %{runtime_us: ["can't be blank"]} =
             errors_on(Run.changeset(%Run{}, attrs))

    assert %{runtime_us: ["must be greater than or equal to 0"]} =
             errors_on(Run.changeset(%Run{}, Map.put(attrs, :runtime_us, -1)))
  end

  test "database rejects a direct negative trial runtime write" do
    assert {:ok, graph} = Graphs.insert(Graph.new("Runtime constraint graph"))

    run =
      Run.new(
        graph: graph,
        seed: 1,
        runtime_us: 5,
        initial_attacker_state: AttackerState.new("source-host")
      )

    assert {:ok, persisted} = Runs.insert(run)

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               "UPDATE simulation_runs SET runtime_us = -1 WHERE id = $1",
               [Ecto.UUID.dump!(persisted.id)]
             )
  end

  test "selects the terminal attacker state by iteration index, not list order" do
    initial = AttackerState.new("source-host")
    mid = AttackerState.new("mid-host")
    terminal = AttackerState.new("terminal-host")

    run = %Run{
      id: Ecto.UUID.generate(),
      graph_revision_id: Ecto.UUID.generate(),
      seed: 1,
      trial_index: 0,
      initial_attacker_state: initial,
      iterations: [
        IterationStep.new(index: 1, success?: false, attacker_state: mid),
        IterationStep.new(index: 3, success?: false, attacker_state: terminal),
        IterationStep.new(index: 2, success?: false, attacker_state: mid)
      ]
    }

    assert Run.current_attacker_state(run) == terminal
  end
end
