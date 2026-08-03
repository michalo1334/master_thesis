defmodule NetworkDefense.SimulationsTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.{Edge, Graph, Graphs, Node}
  alias NetworkDefense.Nodes.{Host, NetworkSegment, Service}
  alias NetworkDefense.Relationships.{Contains, NetworkReachability, Runs}
  alias NetworkDefense.Simulation.{Experiment, IterationStep, Run, SimulationReport}
  alias NetworkDefense.Simulations

  test "reports load the graph revision pinned by the experiment" do
    assert {:ok, graph} = Graphs.insert(graph("Original"))
    host = Enum.find(Graph.nodes(graph), &(&1.type == Host))

    experiment =
      Experiment.new(
        graph: graph,
        master_seed: 1,
        iteration_count: 1,
        max_attempts: 1,
        total_trials: 1,
        completed_trials: 1,
        status: "completed"
      )
      |> Experiment.changeset(%{})
      |> Repo.insert!()

    run =
      Run.new(
        graph: graph,
        experiment_id: experiment.id,
        seed: 1,
        initial_attacker_state: AttackerState.new(host.id)
      )
      |> Run.changeset(%{})
      |> Repo.insert!()

    %IterationStep{run_id: run.id}
    |> IterationStep.changeset(%{
      index: 1,
      success?: false,
      attacker_state: AttackerState.new(host.id)
    })
    |> Repo.insert!()

    assert {:ok, revised} = Graphs.append_optimization(%{graph | title: "Optimized"})
    assert revised.revision_id != graph.revision_id

    assert %SimulationReport{graph_title: "Original", graph_revision_id: revision_id} =
             Simulations.get_report(experiment.id)

    assert revision_id == graph.revision_id
  end

  test "lists experiments by their graph revision" do
    assert {:ok, graph} = Graphs.insert(graph("Topology"))

    experiment =
      Experiment.new(
        graph: graph,
        master_seed: 1,
        iteration_count: 1,
        total_trials: 1,
        completed_trials: 1,
        status: "completed"
      )
      |> Experiment.changeset(%{})
      |> Repo.insert!()

    experiment_id = experiment.id

    assert [^experiment_id] =
             graph.revision_id |> Simulations.list_experiments() |> Enum.map(& &1.id)
  end

  test "keeps operational reachability as a valid in-memory marker" do
    graph = operational_graph("Operational")

    assert [%{type: NetworkReachability, data: %NetworkReachability{}}] = Graph.edges(graph)
    assert {:error, :invalid_edge} = Graphs.insert(graph)
  end

  defp graph(title) do
    graph = Graph.new(title)

    segment =
      Node.new(graph.id, %{
        type: Atom.to_string(NetworkSegment),
        data: %{"name" => "External"},
        view_data: %{"x_pos" => 0, "y_pos" => -100}
      })

    host =
      Node.new(graph.id, %{
        type: Atom.to_string(Host),
        data: %{"name" => "host"},
        view_data: %{"x_pos" => 0, "y_pos" => 0}
      })

    service =
      Node.new(graph.id, %{
        type: Atom.to_string(Service),
        data: %{"name" => "ssh", "protocol" => "tcp", "port" => 22},
        view_data: %{"x_pos" => 100, "y_pos" => 0}
      })

    graph
    |> Graph.add_node(segment)
    |> Graph.add_node(host)
    |> Graph.add_node(service)
    |> Graph.add_edge(
      Edge.new(graph.id, segment.id, host.id, %{type: Atom.to_string(Contains), data: %{}})
    )
    |> Graph.add_edge(
      Edge.new(graph.id, host.id, service.id, %{type: Atom.to_string(Runs), data: %{}})
    )
  end

  defp operational_graph(title) do
    graph = Graph.new(title)

    host =
      Node.new(graph.id, %{
        type: Atom.to_string(Host),
        data: %{"name" => "host"},
        view_data: %{"x_pos" => 0, "y_pos" => 0}
      })

    service =
      Node.new(graph.id, %{
        type: Atom.to_string(Service),
        data: %{"name" => "ssh", "protocol" => "tcp", "port" => 22},
        view_data: %{"x_pos" => 100, "y_pos" => 0}
      })

    graph
    |> Graph.add_node(host)
    |> Graph.add_node(service)
    |> Graph.add_edge(
      Edge.new(graph.id, host.id, service.id, %{
        type: Atom.to_string(NetworkReachability),
        data: %{}
      })
    )
  end
end
