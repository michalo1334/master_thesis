defmodule NetworkDefense.SimulationsTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.{Graph, Node}
  alias NetworkDefense.Nodes.{Host, Service}
  alias NetworkDefense.Relationships.NetworkReachability
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
    graph = insert_graph()
    source = insert_host(graph, "source-host")
    service = insert_service(graph, "ssh")
    insert_reachability(source, service)
    attacker_state = AttackerState.new(source.id)

    experiment =
      %Experiment{graph_id: graph.id}
      |> Experiment.changeset(%{
        master_seed: 1,
        iteration_count: 2,
        max_attempts: 1,
        total_trials: 1
      })
      |> Repo.insert!()

    run =
      %Run{graph_id: graph.id, experiment_id: experiment.id}
      |> Run.changeset(%{
        seed: 1,
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

    assert [_, _] = Graph.nodes(report.graph)
    assert [_] = Graph.edges(report.graph)

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

  defp insert_host(graph, name) do
    %Node{graph_id: graph.id}
    |> Node.changeset(%{
      type: Atom.to_string(Host),
      data: %{"name" => name},
      view_data: %{"x_pos" => 0, "y_pos" => 0}
    })
    |> Repo.insert!()
  end

  defp insert_service(graph, name) do
    %Node{graph_id: graph.id}
    |> Node.changeset(%{
      type: Atom.to_string(Service),
      data: %{"name" => name, "protocol" => "tcp", "port" => 22},
      view_data: %{"x_pos" => 120, "y_pos" => 0}
    })
    |> Repo.insert!()
  end

  defp insert_reachability(source, target) do
    %NetworkDefense.Graph.Edge{graph_id: source.graph_id, from_id: source.id, to_id: target.id}
    |> NetworkDefense.Graph.Edge.changeset(%{
      type: Atom.to_string(NetworkReachability),
      data: %{"protocol" => "tcp", "port_start" => 22, "port_end" => 22}
    })
    |> Repo.insert!()
  end

  defp insert_experiment(graph_id, _attacker_state, inserted_at) do
    %Experiment{
      graph_id: graph_id,
      inserted_at: inserted_at,
      updated_at: inserted_at
    }
    |> Experiment.changeset(%{
      master_seed: 1,
      iteration_count: 1,
      max_attempts: 1,
      total_trials: 1
    })
    |> Repo.insert!()
  end

  defp insert_iteration(run, attacker_state, index) do
    action = %NetworkDefense.Actions.ExploitVulnerability{
      source_host_id: "source",
      supporting_edge_ids: []
    }

    %IterationStep{run_id: run.id}
    |> IterationStep.changeset(%{
      index: index,
      success?: true,
      attempted_action: NetworkDefense.Actions.AttemptedAction.new(action),
      attacker_state: attacker_state
    })
    |> Repo.insert!()
  end
end
