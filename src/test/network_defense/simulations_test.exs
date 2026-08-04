defmodule NetworkDefense.SimulationsTest do
  use NetworkDefense.DataCase, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.{Edge, Graph, Graphs, Node}
  alias NetworkDefense.Nodes.{Host, NetworkSegment, Service, Vulnerability}

  alias NetworkDefense.Relationships.{
    Contains,
    HasVulnerability,
    NetworkReachability,
    Runs,
    SegmentReachability
  }

  alias NetworkDefense.Simulation.Contracts.{RunSimulationRequest, SimulationParams}
  alias NetworkDefense.Simulation.{Experiment, Experiments, IterationStep, Run, SimulationReport}
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

  test "dispatch and batch path simulates an unmaterialized canonical graph" do
    assert {:ok, graph} = Graphs.insert(canonical_graph("Canonical Dispatch"))

    foothold =
      Enum.find(Graph.nodes(graph), &(&1.type == Host and &1.data.name == "source"))

    correlation_id = "canonical-dispatch"

    refute Enum.any?(Graph.edges(graph), &(&1.type == NetworkReachability))

    Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

    {:ok, task} =
      Simulations.run_async(%RunSimulationRequest{
        graph_revision_id: graph.revision_id,
        correlation_id: correlation_id,
        simulation_params: %SimulationParams{
          monte_carlo_trials: 5,
          iterations_per_run: 1,
          initial_foothold_node_id: foothold.id,
          generate_seed: false,
          seed: 42,
          max_attempts: 1
        }
      })

    Sandbox.allow(Repo, self(), task)

    assert_receive {:simulation_completed,
                    %{correlation_id: ^correlation_id, experiment_id: experiment_id}},
                   5_000

    assert %{status: "completed", total_trials: 5, completed_trials: 5} =
             Experiments.get(experiment_id)

    assert %{runs: runs} = Experiments.load(experiment_id)

    assert Enum.all?(runs, fn run ->
             1 < run |> Run.current_attacker_state() |> AttackerState.foothold_nodes() |> length()
           end)
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

  defp canonical_graph(title) do
    graph = Graph.new(title)

    source_segment =
      Node.new(graph.id, %{
        type: Atom.to_string(NetworkSegment),
        data: %{"name" => "External"},
        view_data: %{"x_pos" => 0, "y_pos" => -100}
      })

    source_host =
      Node.new(graph.id, %{
        type: Atom.to_string(Host),
        data: %{"name" => "source"},
        view_data: %{"x_pos" => 0, "y_pos" => -50}
      })

    target_segment =
      Node.new(graph.id, %{
        type: Atom.to_string(NetworkSegment),
        data: %{"name" => "Internal"},
        view_data: %{"x_pos" => 0, "y_pos" => 0}
      })

    target_host =
      Node.new(graph.id, %{
        type: Atom.to_string(Host),
        data: %{"name" => "target"},
        view_data: %{"x_pos" => 0, "y_pos" => 50}
      })

    service =
      Node.new(graph.id, %{
        type: Atom.to_string(Service),
        data: %{"name" => "ssh", "protocol" => "tcp", "port" => 22},
        view_data: %{"x_pos" => 100, "y_pos" => 50}
      })

    vulnerability =
      Node.new(graph.id, %{
        type: Atom.to_string(Vulnerability),
        data: %{
          "identifier" => "CVE-2024-0001",
          "cvss" => cvss(),
          "exploit_probability" => 1.0
        },
        view_data: %{"x_pos" => 200, "y_pos" => 50}
      })

    graph
    |> Graph.add_node(source_segment)
    |> Graph.add_node(source_host)
    |> Graph.add_node(target_segment)
    |> Graph.add_node(target_host)
    |> Graph.add_node(service)
    |> Graph.add_node(vulnerability)
    |> Graph.add_edge(
      Edge.new(graph.id, source_segment.id, source_host.id, %{
        type: Atom.to_string(Contains),
        data: %{}
      })
    )
    |> Graph.add_edge(
      Edge.new(graph.id, target_segment.id, target_host.id, %{
        type: Atom.to_string(Contains),
        data: %{}
      })
    )
    |> Graph.add_edge(
      Edge.new(graph.id, source_segment.id, target_segment.id, %{
        type: Atom.to_string(SegmentReachability),
        data: %{"protocol" => "tcp"}
      })
    )
    |> Graph.add_edge(
      Edge.new(graph.id, target_host.id, service.id, %{
        type: Atom.to_string(Runs),
        data: %{}
      })
    )
    |> Graph.add_edge(
      Edge.new(graph.id, service.id, vulnerability.id, %{
        type: Atom.to_string(HasVulnerability),
        data: %{"required_privilege" => "none", "granted_privilege" => "user"}
      })
    )
  end

  defp cvss do
    %{
      "attack_vector" => "network",
      "attack_complexity" => "low",
      "privileges_required" => "none",
      "user_interaction" => "none",
      "scope" => "unchanged",
      "confidentiality_impact" => "high",
      "integrity_impact" => "none",
      "availability_impact" => "none"
    }
  end
end
