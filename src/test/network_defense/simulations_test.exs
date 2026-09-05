defmodule NetworkDefense.SimulationsTest do
  use NetworkDefense.DataCase, async: false
  use Oban.Testing, repo: NetworkDefense.Repo

  import Ecto.Query

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.{Edge, Graph, Graphs, Node}
  alias NetworkDefense.Nodes.{Host, MissionCapability, NetworkSegment, Service, Vulnerability}

  alias NetworkDefense.Relationships.{
    Contains,
    HasVulnerability,
    NetworkReachability,
    Runs,
    SegmentReachability,
    Supports
  }

  alias NetworkDefense.Simulation.Contracts.{RunSimulationRequest, SimulationParams}
  alias NetworkDefense.Simulation.{Experiment, Experiments, IterationStep, Run, SimulationReport}
  alias NetworkDefense.Simulations
  alias NetworkDefense.Simulations.SimulationWorker

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
        status: :completed
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
        status: :completed
      )
      |> Experiment.changeset(%{})
      |> Repo.insert!()

    experiment_id = experiment.id

    assert [^experiment_id] =
             [graph.revision_id] |> Simulations.list_experiments() |> Enum.map(& &1.id)
  end

  test "keeps operational reachability as a valid in-memory marker" do
    graph = operational_graph("Operational")

    assert [%{type: NetworkReachability, data: %NetworkReachability{}}] = Graph.edges(graph)
    assert {:error, :invalid_edge} = Graphs.insert(graph)
  end

  test "dispatch simulates an unmaterialized canonical graph" do
    assert {:ok, graph} = Graphs.insert(canonical_graph("Canonical Dispatch"))

    foothold =
      Enum.find(Graph.nodes(graph), &(&1.type == Host and &1.data.name == "source"))

    correlation_id = "canonical-dispatch"

    refute Enum.any?(Graph.edges(graph), &(&1.type == NetworkReachability))

    Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

    assert {:ok, _job} =
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

    assert [
             %{
               args: %{"experiment_id" => experiment_id, "correlation_id" => ^correlation_id},
               queue: "simulations",
               max_attempts: 1,
               meta: %{"traceparent" => _}
             }
           ] = all_enqueued(worker: SimulationWorker)

    assert :ok =
             perform_job(SimulationWorker, %{
               "experiment_id" => experiment_id,
               "correlation_id" => correlation_id
             })

    assert_receive {:simulation_completed,
                    %{correlation_id: ^correlation_id, experiment_id: ^experiment_id}},
                   5_000

    assert %{status: :completed, total_trials: 5, completed_trials: 5} =
             Experiments.get(experiment_id)

    assert %{runs: runs} = Experiments.load(experiment_id)

    assert Enum.all?(runs, fn run ->
             1 < run |> Run.current_attacker_state() |> AttackerState.foothold_nodes() |> length()
           end)
  end

  test "rejects an invalid initial foothold with an error tuple, not task-start success" do
    assert {:ok, graph} = Graphs.insert(canonical_graph("Invalid Foothold"))

    assert {:error, :invalid_initial_foothold} =
             Simulations.run_async(%RunSimulationRequest{
               graph_revision_id: graph.revision_id,
               correlation_id: "invalid-foothold-request",
               simulation_params: %SimulationParams{
                 monte_carlo_trials: 1,
                 iterations_per_run: 1,
                 initial_foothold_node_id: Ecto.UUID.generate(),
                 generate_seed: false,
                 seed: 42,
                 max_attempts: 1
               }
             })
  end

  test "rejects a graph with declared but unavailable required flows before persisting" do
    assert {:ok, graph} = Graphs.insert(mission_graph("Infeasible Mission", missing_flow: true))

    foothold =
      Enum.find(Graph.nodes(graph), &(&1.type == Host and &1.data.name == "source"))

    assert {:error, :infeasible_input} =
             Simulations.run_async(%RunSimulationRequest{
               graph_revision_id: graph.revision_id,
               correlation_id: "infeasible-mission-request",
               simulation_params: %SimulationParams{
                 monte_carlo_trials: 1,
                 iterations_per_run: 1,
                 initial_foothold_node_id: foothold.id,
                 generate_seed: false,
                 seed: 42,
                 max_attempts: 1
               }
             })

    assert Repo.get_by(Experiment, graph_revision_id: graph.revision_id) == nil
  end

  test "prepare rejects a graph with declared but unavailable required flows" do
    assert {:ok, graph} = Graphs.insert(mission_graph("Infeasible Prepare", missing_flow: true))

    foothold =
      Enum.find(Graph.nodes(graph), &(&1.type == Host and &1.data.name == "source"))

    assert {:error, :infeasible_input} =
             Simulations.run_async(%RunSimulationRequest{
               graph_revision_id: graph.revision_id,
               correlation_id: "infeasible-prepare-request",
               simulation_params: %SimulationParams{
                 monte_carlo_trials: 1,
                 iterations_per_run: 1,
                 initial_foothold_node_id: foothold.id,
                 generate_seed: false,
                 seed: 42,
                 max_attempts: 1
               }
             })

    assert Repo.get_by(Experiment, graph_revision_id: graph.revision_id) == nil
  end

  test "runs a graph whose declared required flows are available" do
    assert {:ok, graph} = Graphs.insert(mission_graph("Feasible Mission"))

    foothold =
      Enum.find(Graph.nodes(graph), &(&1.type == Host and &1.data.name == "source"))

    correlation_id = "feasible-mission"

    Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

    assert {:ok, _job} =
             Simulations.run_async(%RunSimulationRequest{
               graph_revision_id: graph.revision_id,
               correlation_id: correlation_id,
               simulation_params: %SimulationParams{
                 monte_carlo_trials: 1,
                 iterations_per_run: 1,
                 initial_foothold_node_id: foothold.id,
                 generate_seed: false,
                 seed: 42,
                 max_attempts: 1
               }
             })

    assert [
             %{
               args: %{"experiment_id" => experiment_id, "correlation_id" => ^correlation_id},
               queue: "simulations",
               max_attempts: 1,
               meta: %{"traceparent" => _}
             }
           ] = all_enqueued(worker: SimulationWorker)

    assert :ok =
             perform_job(SimulationWorker, %{
               "experiment_id" => experiment_id,
               "correlation_id" => correlation_id
             })

    assert_receive {:simulation_completed, %{correlation_id: ^correlation_id}}, 5_000
  end

  test "rejects an experiment persistence failure with an error tuple" do
    assert {:ok, graph} = Graphs.insert(canonical_graph("Create Failure"))

    foothold =
      Enum.find(Graph.nodes(graph), &(&1.type == Host and &1.data.name == "source"))

    assert {:error, _reason} =
             Simulations.run_async(%RunSimulationRequest{
               graph_revision_id: graph.revision_id,
               correlation_id: "create-failure-request",
               simulation_params: %SimulationParams{
                 monte_carlo_trials: 1,
                 iterations_per_run: 1,
                 initial_foothold_node_id: foothold.id,
                 generate_seed: false,
                 seed: nil,
                 max_attempts: 1
               }
             })
  end

  test "marks an experiment failed when final persistence fails" do
    assert {:ok, graph} = Graphs.insert(canonical_graph("Post Persistence Failure"))

    foothold =
      Enum.find(Graph.nodes(graph), &(&1.type == Host and &1.data.name == "source"))

    correlation_id = "post-persistence-failure"

    experiment =
      Experiment.new(
        graph: graph,
        master_seed: 42,
        iteration_count: 1,
        max_attempts: 1,
        total_trials: 2,
        initial_foothold_node_id: foothold.id,
        status: :running
      )
      |> Experiment.changeset(%{})
      |> Repo.insert!()

    Enum.each(1..2, fn trial_index ->
      Run.new(
        graph: graph,
        experiment_id: experiment.id,
        seed: trial_index,
        trial_index: trial_index,
        initial_attacker_state: AttackerState.new(foothold.id)
      )
      |> Run.changeset(%{})
      |> Repo.insert!()
    end)

    assert {:error, :internal_error} =
             Simulations.run(experiment.id, correlation_id: correlation_id)

    assert %{status: :failed} = Experiments.get(experiment.id)

    assert 2 ==
             Repo.aggregate(from(run in Run, where: run.experiment_id == ^experiment.id), :count)
  end

  test "simulation worker leaves execution failure ownership in the context" do
    assert {:ok, graph} = Graphs.insert(canonical_graph("Worker Failure"))

    experiment =
      Experiment.new(
        graph: graph,
        master_seed: 42,
        iteration_count: 1,
        max_attempts: 1,
        total_trials: 2,
        completed_trials: 0,
        status: :running
      )
      |> Experiment.changeset(%{})
      |> Repo.insert!()

    assert {:error, :internal_error} =
             Simulations.run(experiment.id, correlation_id: "worker-failure-correlation")

    assert {:error, :failed} =
             perform_job(SimulationWorker, %{
               "experiment_id" => experiment.id,
               "correlation_id" => "worker-failure-correlation"
             })

    assert %{status: :failed} = Experiments.get(experiment.id)
  end

  test "completes a fully persisted running experiment during workflow recovery" do
    assert {:ok, graph} = Graphs.insert(canonical_graph("Recovered Completion"))
    foothold = Enum.find(Graph.nodes(graph), &(&1.type == Host and &1.data.name == "source"))

    experiment =
      Experiment.new(
        graph: graph,
        master_seed: 1,
        iteration_count: 1,
        max_attempts: 1,
        total_trials: 1,
        completed_trials: 1,
        initial_foothold_node_id: foothold.id,
        status: :running
      )
      |> Experiment.changeset(%{})
      |> Repo.insert!()

    assert {:error, :partial_experiment_unsupported} =
             Simulations.run(experiment.id, correlation_id: "recovered-completion")

    assert %{status: :running} = Experiments.get(experiment.id)
  end

  test "publishes weighted simulation progress" do
    assert {:ok, graph} = Graphs.insert(canonical_graph("Simulation Progress"))
    foothold = Enum.find(Graph.nodes(graph), &(&1.type == Host and &1.data.name == "source"))

    experiment =
      Experiment.new(
        graph: graph,
        master_seed: 19,
        iteration_count: 1,
        max_attempts: 1,
        total_trials: 2,
        initial_foothold_node_id: foothold.id
      )
      |> Experiments.create()
      |> elem(1)

    correlation_id = "weighted-progress"
    Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

    assert {:ok, _} =
             Simulations.run(experiment.id,
               correlation_id: correlation_id,
               max_concurrency: 1,
               publish_events: true
             )

    assert_receive {:simulation_progress,
                    %{
                      correlation_id: ^correlation_id,
                      graph_id: graph_id,
                      graph_revision_id: graph_revision_id,
                      completed: 2,
                      total: 2
                    }}

    assert graph_id == graph.id
    assert graph_revision_id == graph.revision_id
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

  defp mission_graph(title, opts \\ []) do
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

    capability =
      Node.new(graph.id, %{
        type: Atom.to_string(MissionCapability),
        data: %{
          "name" => "orders",
          "impact_weight" => 8.0,
          "min_operational_support" => 1,
          "required_flows" => [
            %{"source_segment_id" => source_segment.id, "target_service_id" => service.id}
          ]
        },
        view_data: %{"x_pos" => 200, "y_pos" => 0}
      })

    graph
    |> Graph.add_node(source_segment)
    |> Graph.add_node(source_host)
    |> Graph.add_node(target_segment)
    |> Graph.add_node(target_host)
    |> Graph.add_node(service)
    |> Graph.add_node(capability)
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
    |> maybe_add_policy(source_segment, target_segment, opts)
    |> Graph.add_edge(
      Edge.new(graph.id, target_host.id, service.id, %{
        type: Atom.to_string(Runs),
        data: %{}
      })
    )
    |> Graph.add_edge(
      Edge.new(graph.id, source_host.id, capability.id, %{
        type: Atom.to_string(Supports),
        data: %{}
      })
    )
    |> Graph.add_edge(
      Edge.new(graph.id, target_host.id, capability.id, %{
        type: Atom.to_string(Supports),
        data: %{}
      })
    )
  end

  defp maybe_add_policy(graph, source_segment, target_segment, opts) do
    if Keyword.get(opts, :missing_flow) do
      graph
    else
      Graph.add_edge(
        graph,
        Edge.new(graph.id, source_segment.id, target_segment.id, %{
          type: Atom.to_string(SegmentReachability),
          data: %{"protocol" => "tcp"}
        })
      )
    end
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
