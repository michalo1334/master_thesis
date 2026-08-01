defmodule NetworkDefenseWeb.DashboardLiveTest do
  use NetworkDefenseWeb.ConnCase

  import Phoenix.LiveViewTest

  alias NetworkDefense.Graph.{Edge, Graph}
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Runs
  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Simulations

  describe "mount" do
    test "renders the Svelte dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end

    test "renders hidden recovery flashes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#client-error[hidden][phx-disconnected][phx-connected]")
      assert has_element?(view, "#server-error[hidden][phx-disconnected][phx-connected]")
    end
  end

  describe "fetch_graph_connectivity" do
    test "returns backend semantic connectivity rules", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_graph_connectivity", %{})

      assert_reply(view, %{rules: rules})

      assert %{from_type: "Host", relationship_type: "Runs", to_type: "Service"} in rules
    end
  end

  describe "graph drafts" do
    test "returns a validated node draft", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "create_node_draft", %{
        "node_type" => "Host",
        "x_pos" => 30,
        "y_pos" => 40
      })

      assert_reply(view, %{
        status: "ok",
        node: %{type: "Host", data: %{name: "New host"}, view_data: %{x_pos: 30.0, y_pos: 40.0}}
      })
    end

    test "returns a reverse-directed connection draft", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      service_id = Ecto.UUID.generate()
      host_id = Ecto.UUID.generate()

      render_hook(view, "create_connection_draft", %{
        "relationship_type" => "Runs",
        "source_id" => service_id,
        "source_type" => "Service",
        "source_is_from" => false,
        "target_id" => host_id,
        "target_type" => "Host"
      })

      assert_reply(view, %{
        status: "ok",
        edge: %{type: "Runs", from_id: ^host_id, to_id: ^service_id, data: %{}}
      })
    end

    test "rejects an invalid connection draft", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "create_connection_draft", %{
        "relationship_type" => "Runs",
        "source_id" => Ecto.UUID.generate(),
        "source_type" => "Service",
        "source_is_from" => true,
        "target_id" => Ecto.UUID.generate(),
        "target_type" => "Host"
      })

      assert_reply(view, %{status: "invalid", edge: nil, node: nil})
    end
  end

  describe "open_graph" do
    test "accepts an existing graph", %{conn: conn} do
      graph = insert_graph("dwg-001")
      source = insert_node(graph, "origin")
      target = insert_service(Graphs.load_revision!(source.graph_revision_id), "dest")
      edge = insert_edge(source, target)
      graph = Graphs.load_revision!(edge.graph_revision_id)

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "open_graph", %{"graph_revision_id" => graph.revision_id})

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end

    test "accepts a missing graph_revision_id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "open_graph", %{
        "graph_revision_id" => "00000000-0000-0000-0000-000000000000"
      })

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end

    test "accepts an open request without graph_revision_id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "open_graph", %{})

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end
  end

  describe "compare_graphs" do
    test "rejects an invalid base graph", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "compare_graphs", %{})

      assert_reply(view, %{status: "invalid_graph", result: nil})
    end

    test "reports a missing comparison revision", %{conn: conn} do
      base = insert_graph("base")
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "compare_graphs", %{
        "base_revision_id" => base.revision_id,
        "comparison_revision_id" => "00000000-0000-0000-0000-000000000000"
      })

      assert_reply(view, %{status: "not_found", result: nil})
    end

    test "returns a merged structural result for two persisted revisions", %{conn: conn} do
      base = insert_graph("base")
      source = insert_node(base, "source")
      target = insert_service(Graphs.load_revision!(source.graph_revision_id), "target")
      edge = insert_edge(source, target)
      base = Graphs.load_revision!(edge.graph_revision_id)
      assert {:ok, comparison} = Graphs.append_optimization(%{base | title: "comparison"})

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "compare_graphs", %{
        "base_revision_id" => base.revision_id,
        "comparison_revision_id" => comparison.revision_id
      })

      assert_reply(view, %{
        status: "ok",
        result: %{
          graph: %{id: result_graph_id, title: "base"},
          node_counts: %{added: 0, removed: 0, unchanged: 2},
          edge_counts: %{added: 0, removed: 0, unchanged: 1},
          node_status: node_status,
          edge_status: edge_status
        }
      })

      assert result_graph_id == base.id
      assert Enum.all?(node_status, &(&1.status == "unchanged"))
      assert Enum.all?(edge_status, &(&1.status == "unchanged"))
    end
  end

  describe "simulation events" do
    test "returns invalid_params for an invalid report request", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_simulation_report", %{})

      assert_reply(view, %{status: "invalid_params"})
    end

    test "rejects a report request for another graph revision", %{conn: conn} do
      graph = insert_graph("versioned-report")
      foothold = insert_node(graph, "entry-host")
      correlation_id = "versioned-report-request"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

      render_hook(view, "run_simulation_request", %{
        "request" => %{
          "graph_revision_id" => foothold.graph_revision_id,
          "correlation_id" => correlation_id,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1,
            "initial_foothold_node_id" => foothold.id,
            "generate_seed" => true
          }
        }
      })

      assert_receive {:simulation_completed,
                      %{correlation_id: ^correlation_id, experiment_id: experiment_id}},
                     5_000

      assert {:ok, revised} =
               Graphs.append_optimization(%{
                 Graphs.load_revision!(foothold.graph_revision_id)
                 | title: "changed topology"
               })

      revised_revision_id = revised.revision_id

      render_hook(view, "fetch_simulation_report", %{
        "experiment_id" => experiment_id,
        "graph_revision_id" => revised_revision_id
      })

      assert_reply(view, %{status: "processing"})

      assert_push_event(view, "simulation_report_error", %{
        experiment_id: ^experiment_id,
        graph_revision_id: ^revised_revision_id,
        reason: "not_found"
      })
    end

    test "accepts a correlated simulation request and broadcasts its completion", %{conn: conn} do
      graph = insert_graph("run-sim-test")
      graph_id = graph.id
      foothold = insert_node(graph, "entry-host")
      correlation_id = "request-123"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

      render_hook(view, "run_simulation_request", %{
        "request" => %{
          "graph_revision_id" => foothold.graph_revision_id,
          "correlation_id" => correlation_id,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1,
            "initial_foothold_node_id" => foothold.id,
            "generate_seed" => true
          }
        }
      })

      assert_reply(view, %{
        status: "accepted",
        graph_revision_id: graph_revision_id,
        correlation_id: ^correlation_id,
        reason: nil
      })

      assert has_element?(view, "#flash-info[role='alert']")

      assert_receive {:simulation_completed,
                      %{
                        correlation_id: ^correlation_id,
                        graph_id: ^graph_id,
                        graph_revision_id: ^graph_revision_id,
                        experiment_id: experiment_id
                      }},
                     5_000

      assert is_binary(experiment_id)
      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end

    test "commits a simulation across trial batches", %{conn: conn} do
      graph = insert_graph("batched-simulation")
      foothold = insert_node(graph, "entry-host")
      correlation_id = "batched-simulation-request"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

      render_hook(view, "run_simulation_request", %{
        "request" => %{
          "graph_revision_id" => foothold.graph_revision_id,
          "correlation_id" => correlation_id,
          "simulation_params" => %{
            "monte_carlo_trials" => 101,
            "iterations_per_run" => 1,
            "initial_foothold_node_id" => foothold.id,
            "generate_seed" => true
          }
        }
      })

      assert_receive {:simulation_completed,
                      %{correlation_id: ^correlation_id, experiment_id: experiment_id}},
                     5_000

      assert %{status: "completed", total_trials: 101, completed_trials: 101} =
               Experiments.get(experiment_id)
    end

    test "rejects a simulation request with nil seed and generate_seed false", %{conn: conn} do
      graph = insert_graph("nil-seed-test")
      graph_revision_id = graph.revision_id
      correlation_id = "request-nil-seed"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_simulation_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1
          }
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_revision_id: ^graph_revision_id,
        correlation_id: ^correlation_id,
        reason: "invalid_request"
      })
    end

    test "rejects an invalid correlated simulation request", %{conn: conn} do
      correlation_id = "request-456"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_simulation_request", %{
        "request" => %{
          "graph_revision_id" => "not-a-uuid",
          "correlation_id" => correlation_id,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1
          }
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_revision_id: "not-a-uuid",
        correlation_id: ^correlation_id,
        reason: "invalid_request"
      })
    end

    test "rejects a simulation request without valid parameters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_simulation_request", %{})

      assert_reply(view, %{
        status: "rejected",
        graph_revision_id: "",
        correlation_id: "",
        reason: "invalid_request"
      })
    end

    test "forwards simulation completion and failure events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      completed = %{
        correlation_id: "request-1",
        graph_id: "graph-1",
        graph_revision_id: "revision-1",
        experiment_id: "experiment-1"
      }

      send(view.pid, {:simulation_completed, completed})
      assert_push_event(view, "simulation_completed", ^completed)

      failed = %{
        correlation_id: "request-2",
        graph_id: "graph-2",
        graph_revision_id: "revision-2",
        reason: "persistence_failed"
      }

      send(view.pid, {:simulation_failed, failed})
      assert_push_event(view, "simulation_failed", ^failed)
      assert has_element?(view, "#flash-error[role='alert']")
    end
  end

  describe "optimization events" do
    test "accepts an optimization request and persists an optimized graph", %{conn: conn} do
      graph = insert_graph("optimize-test")
      foothold = insert_node(graph, "entry-host")
      graph = Graphs.load_revision!(foothold.graph_revision_id)
      graph_id = graph.id
      graph_revision_id = graph.revision_id
      correlation_id = "optimization-request"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Optimizations.optimization_events_topic())

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{"strategy" => "cvss", "budget" => 1}
        }
      })

      assert_reply(view, %{
        status: "accepted",
        graph_revision_id: ^graph_revision_id,
        correlation_id: ^correlation_id,
        reason: nil
      })

      assert has_element?(view, "#flash-info[role='alert']")

      assert graph_id == graph.id

      assert_receive {:optimization_completed,
                      %{
                        correlation_id: ^correlation_id,
                        graph_id: ^graph_id,
                        graph_revision_id: optimized_revision_id,
                        report: %{
                          strategy: "cvss",
                          requested_budget: 1,
                          used_budget: 0,
                          runtime_ms: runtime_ms,
                          actions: []
                        }
                      }},
                     5_000

      assert runtime_ms >= 0

      assert %{
               id: ^graph_id,
               parent_revision_id: ^graph_revision_id,
               revision_kind: :optimization,
               title: "optimize-test"
             } =
               Graphs.load_revision(optimized_revision_id)
    end

    test "accepts topology segmentation optimization", %{conn: conn} do
      assert_strategy_optimization(
        conn,
        "topology_segmentation",
        "Topology segmentation strategy"
      )
    end

    test "accepts simulated annealing optimization", %{conn: conn} do
      assert_strategy_optimization(
        conn,
        "simulated_annealing",
        "Simulation-informed simulated annealing strategy"
      )
    end

    test "optimizes a graph with the maximum title length", %{conn: conn} do
      graph = insert_graph(String.duplicate("x", 255))
      graph_id = graph.id
      graph_revision_id = graph.revision_id
      graph_title = graph.title
      correlation_id = "optimization-title-too-long"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Optimizations.optimization_events_topic())

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{"strategy" => "cvss", "budget" => 1}
        }
      })

      assert_reply(view, %{
        status: "accepted",
        graph_revision_id: ^graph_revision_id,
        correlation_id: ^correlation_id,
        reason: nil
      })

      assert_receive {:optimization_completed,
                      %{
                        correlation_id: ^correlation_id,
                        graph_id: ^graph_id,
                        graph_revision_id: optimized_revision_id
                      }},
                     5_000

      assert %{title: ^graph_title} = Graphs.load_revision(optimized_revision_id)
    end

    test "rejects invalid optimization parameters", %{conn: conn} do
      graph = insert_graph("invalid-optimization")
      graph_revision_id = graph.revision_id
      correlation_id = "invalid-optimization-request"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{"strategy" => "cvss", "budget" => 0}
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_revision_id: ^graph_revision_id,
        correlation_id: ^correlation_id,
        reason: "invalid_request"
      })
    end

    test "requires simulation parameters for simulation-informed optimization", %{conn: conn} do
      graph = insert_graph("simulation-informed-optimization")
      graph_revision_id = graph.revision_id
      correlation_id = "simulation-informed-request"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{"strategy" => "simulation_informed", "budget" => 1}
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_revision_id: ^graph_revision_id,
        correlation_id: ^correlation_id,
        reason: "invalid_request"
      })
    end

    test "rejects a foothold that is not a host in the graph", %{conn: conn} do
      graph = insert_graph("invalid-foothold-optimization")
      graph_revision_id = graph.revision_id
      correlation_id = "invalid-foothold-request"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{
            "strategy" => "topology_segmentation",
            "budget" => 1,
            "simulation_params" => %{
              "monte_carlo_trials" => 1,
              "iterations_per_run" => 1,
              "initial_foothold_node_id" => Ecto.UUID.generate(),
              "generate_seed" => true,
              "max_attempts" => 1
            }
          }
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_revision_id: ^graph_revision_id,
        correlation_id: ^correlation_id,
        reason: "initial foothold must identify a host in the graph"
      })
    end

    test "forwards optimization completion and failure events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      completed = %{
        correlation_id: "optimization-1",
        graph_id: "graph-1",
        graph_revision_id: "revision-1",
        report: %{
          strategy: "cvss",
          requested_budget: 1,
          used_budget: 1,
          runtime_ms: 1,
          actions: [
            %{
              id: "patch-1",
              label: "Patch CVE-1",
              kind: "Vulnerability patch",
              cost: 1,
              cvss_score: nil
            }
          ]
        }
      }

      send(view.pid, {:optimization_completed, completed})
      assert_push_event(view, "optimization_completed", ^completed)

      failed = %{
        correlation_id: "optimization-2",
        graph_id: "graph-2",
        graph_revision_id: "revision-2",
        reason: "optimization_failed"
      }

      send(view.pid, {:optimization_failed, failed})
      assert_push_event(view, "optimization_failed", ^failed)
      assert has_element?(view, "#flash-error[role='alert']")

      progress = %{
        correlation_id: "optimization-3",
        graph_id: "graph-3",
        graph_revision_id: "revision-3",
        completed_steps: 1,
        total_steps: 2,
        phase: "Applied defense 1 of 2"
      }

      send(view.pid, {:optimization_progress, progress})
      assert_push_event(view, "optimization_progress", ^progress)
    end
  end

  describe "save_graph" do
    test "persists graph edges and node view_data", %{conn: conn} do
      graph = insert_graph("save-graph")
      source = insert_node(graph, "source")
      graph = Graphs.load_revision!(source.graph_revision_id)
      target = insert_service(graph, "target")
      edge_id = Ecto.UUID.generate()
      graph = Graphs.load_revision!(target.graph_revision_id)

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "save_graph", %{
        "graph" => %{
          "id" => graph.id,
          "revision_id" => graph.revision_id,
          "title" => "saved graph",
          "nodes" => [
            %{
              "id" => source.id,
              "type" => "Host",
              "data" => NetworkDefense.Graph.Data.to_params(source.data),
              "view_data" => %{"x_pos" => 120, "y_pos" => 240}
            },
            %{
              "id" => target.id,
              "type" => "Service",
              "data" => NetworkDefense.Graph.Data.to_params(target.data),
              "view_data" => %{"x_pos" => 360, "y_pos" => 480}
            }
          ],
          "edges" => [
            %{
              "id" => edge_id,
              "from_id" => source.id,
              "to_id" => target.id,
              "type" => "NetworkReachability",
              "data" => %{"protocol" => "tcp", "port_start" => 443, "port_end" => 443}
            }
          ]
        }
      })

      saved_graph = latest_graph(graph.id)

      assert [%{from_id: source_id, to_id: target_id, type: type}] = Graph.edges(saved_graph)
      assert source_id == source.id
      assert target_id == target.id
      assert type == NetworkReachability
      assert saved_graph.title == "saved graph"
      assert saved_graph.revision_id != graph.revision_id

      source_node = Enum.find(saved_graph.nodes, &(&1.id == source.id))
      target_node = Enum.find(saved_graph.nodes, &(&1.id == target.id))
      assert source_node.view_data.x_pos == 120.0
      assert source_node.view_data.y_pos == 240.0
      assert target_node.view_data.x_pos == 360.0
      assert target_node.view_data.y_pos == 480.0
    end

    test "replaces a selected graph revision", %{conn: conn} do
      graph = insert_graph("stale-graph")

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "save_graph", %{
        "graph" => %{
          "id" => graph.id,
          "revision_id" => graph.revision_id,
          "title" => "stale graph",
          "nodes" => [],
          "edges" => []
        }
      })

      assert latest_graph(graph.id).title == "stale graph"
    end
  end

  defp insert_graph(title) do
    assert {:ok, graph} = Graphs.insert(Graph.new(title))
    graph
  end

  defp assert_strategy_optimization(conn, strategy, _strategy_name) do
    graph = insert_graph("#{strategy}-test")
    foothold = insert_node(graph, "entry-host")
    graph = Graphs.load_revision!(foothold.graph_revision_id)
    correlation_id = "#{strategy}-request"

    {:ok, view, _html} = live(conn, ~p"/")
    Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Optimizations.optimization_events_topic())

    render_hook(view, "run_optimization_request", %{
      "request" => %{
        "graph_revision_id" => graph.revision_id,
        "correlation_id" => correlation_id,
        "optimization_params" => %{
          "strategy" => strategy,
          "budget" => 1,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1,
            "initial_foothold_node_id" => foothold.id,
            "generate_seed" => true,
            "max_attempts" => 1
          }
        }
      }
    })

    assert_reply(view, %{status: "accepted", correlation_id: ^correlation_id})

    assert_receive {:optimization_completed,
                    %{
                      correlation_id: ^correlation_id,
                      graph_revision_id: optimized_revision_id
                    }},
                   5_000

    expected_title = "#{strategy}-test"
    assert %{title: ^expected_title} = Graphs.load_revision(optimized_revision_id)
  end

  defp insert_node(graph, name) do
    node =
      Node.new(graph.id, %{
        type: Atom.to_string(Host),
        data: %{"name" => name},
        view_data: %{"x_pos" => 0, "y_pos" => 0}
      })

    graph.revision_id
    |> Graphs.load_revision!()
    |> Graph.add_node(node)
    |> append_revision()
    |> Graph.node(node.id)
  end

  defp insert_service(graph, name) do
    node =
      Node.new(graph.id, %{
        type: Atom.to_string(Service),
        data: %{"name" => name, "protocol" => "tcp", "port" => 443},
        view_data: %{"x_pos" => 0, "y_pos" => 0}
      })

    graph.revision_id
    |> Graphs.load_revision!()
    |> Graph.add_node(node)
    |> append_revision()
    |> Graph.node(node.id)
  end

  defp insert_edge(source, target) do
    edge =
      Edge.new(source.graph_id, source.id, target.id, %{type: Atom.to_string(Runs), data: %{}})

    target.graph_revision_id
    |> Graphs.load_revision!()
    |> Graph.add_edge(edge)
    |> append_revision()
    |> Graph.edge(edge.id)
  end

  defp append_revision(graph) do
    assert {:ok, graph} = Graphs.append_optimization(graph)
    graph
  end

  defp latest_graph(graph_id) do
    graph_id
    |> then(fn id ->
      Graphs.list_summaries() |> Enum.filter(&(&1.graphId == id)) |> List.last()
    end)
    |> then(&Graphs.load_revision!(&1.revisionId))
  end
end
