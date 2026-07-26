defmodule NetworkDefense.SimulationsTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.{Graph, Node}
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Contracts.SimulationParams
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.SimulationReport
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Simulations

  test "broadcasts a correlated failure when execution fails" do
    graph = %{Graph.new("invalid graph") | nodes: [%Node{type: nil}]}
    correlation_id = Ecto.UUID.generate()

    Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

    assert {:ok, _pid} =
             Simulations.run_async(graph, correlation_id, %SimulationParams{
               monte_carlo_trials: 1,
               iterations_per_run: 1,
               initial_foothold_node_id: "invalid"
             })

    assert_receive {:simulation_failed,
                    %{correlation_id: ^correlation_id, graph_id: graph_id, reason: reason}},
                   5_000

    assert graph_id == graph.id
    assert reason =~ "initial foothold must identify a host"
  end

  test "gets a typed report for a persisted experiment" do
    attacker_state = AttackerState.new("source-host")
    graph = insert_graph()

    experiment =
      %Experiment{graph_id: graph.id}
      |> Experiment.changeset(%{
        seed: 1,
        iteration_count: 2,
        initial_attacker_state: attacker_state
      })
      |> Repo.insert!()

    run =
      %Run{graph_id: graph.id, experiment_id: experiment.id}
      |> Run.changeset(%{
        initial_seed: 1,
        iteration_count: 2,
        initial_attacker_state: attacker_state
      })
      |> Repo.insert!()

    insert_iteration(run, attacker_state, 1)
    insert_iteration(run, attacker_state, 2)

    report = Simulations.get_report(experiment.id)

    assert %SimulationReport{
             graph_title: "Simulation graph",
             run_count: 1,
             charts: %SimulationReport.Charts{
               convergence: [%{run: 1, mean_blast_radius: 1.0}]
             }
           } = report

    assert Simulations.get_report(Ecto.UUID.generate()) == nil
  end

  test "lists experiments most recent first" do
    graph = insert_graph()
    attacker_state = AttackerState.new("source-host")

    older = insert_experiment(graph.id, attacker_state, ~U[2026-01-01 12:00:00Z])
    newer = insert_experiment(graph.id, attacker_state, ~U[2026-01-01 12:01:00Z])
    newer_id = newer.id
    older_id = older.id

    assert [^newer_id, ^older_id] =
             graph.id
             |> Simulations.list_experiments()
             |> Enum.map(& &1.id)
  end

  defp insert_graph do
    %Graph{}
    |> Graph.changeset(%{title: "Simulation graph"})
    |> Repo.insert!()
  end

  defp insert_experiment(graph_id, attacker_state, inserted_at) do
    %Experiment{
      graph_id: graph_id,
      inserted_at: inserted_at,
      updated_at: inserted_at
    }
    |> Experiment.changeset(%{
      seed: 1,
      iteration_count: 1,
      initial_attacker_state: attacker_state
    })
    |> Repo.insert!()
  end

  defp insert_iteration(run, attacker_state, index) do
    %IterationStep{run_id: run.id}
    |> IterationStep.changeset(%{
      index: index,
      success?: true,
      attacker_state: attacker_state,
      seed: :rand.seed_s(:exsss, {1, 2, index})
    })
    |> Repo.insert!()
  end
end
