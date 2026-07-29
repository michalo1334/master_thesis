defmodule NetworkDefenseWeb.DashboardLiveTest do
  use NetworkDefenseWeb.ConnCase

  import Phoenix.LiveViewTest

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Repo
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Runs
  alias NetworkDefense.Simulations

  describe "mount" do
    test "renders the Svelte dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end
  end

  describe "open_graph" do
    test "accepts an existing graph", %{conn: conn} do
      graph = insert_graph("dwg-001")
      source = insert_node(graph, "origin")
      target = insert_service(graph, "dest")
      insert_edge(source, target)

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "open_graph", %{"graph_id" => graph.id})

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end

    test "accepts a missing graph_id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "open_graph", %{
        "graph_id" => "00000000-0000-0000-0000-000000000000"
      })

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end

    test "accepts an open request without graph_id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "open_graph", %{})

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end
  end

  describe "simulation events" do
    test "returns invalid_params for an invalid report request", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_simulation_report", %{})

      assert_reply(view, %{status: "invalid_params"})
    end

    test "reports a topology version mismatch", %{conn: conn} do
      graph = insert_graph("versioned-report")
      graph_id = graph.id
      foothold = insert_node(graph, "entry-host")
      correlation_id = "versioned-report-request"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

      render_hook(view, "run_simulation_request", %{
        "request" => %{
          "graph_id" => graph_id,
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

      assert {:ok, _} =
               Graphs.replace(graph_id, graph.lock_version, %{
                 "title" => "changed topology",
                 "nodes" => [],
                 "edges" => []
               })

      render_hook(view, "fetch_simulation_report", %{
        "experiment_id" => experiment_id,
        "graph_id" => graph_id
      })

      assert_reply(view, %{status: "processing"})

      assert_push_event(view, "simulation_report_error", %{
        experiment_id: ^experiment_id,
        graph_id: ^graph_id,
        reason: "graph_version_mismatch"
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
          "graph_id" => graph_id,
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
        graph_id: ^graph_id,
        correlation_id: ^correlation_id,
        reason: nil
      })

      assert_receive {:simulation_completed,
                      %{
                        correlation_id: ^correlation_id,
                        graph_id: ^graph_id,
                        experiment_id: experiment_id
                      }},
                     5_000

      assert is_binary(experiment_id)
      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end

    test "rejects a simulation request with nil seed and generate_seed false", %{conn: conn} do
      graph = insert_graph("nil-seed-test")
      graph_id = graph.id
      correlation_id = "request-nil-seed"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_simulation_request", %{
        "request" => %{
          "graph_id" => graph_id,
          "correlation_id" => correlation_id,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1
          }
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_id: ^graph_id,
        correlation_id: ^correlation_id,
        reason: "invalid_request"
      })
    end

    test "rejects an invalid correlated simulation request", %{conn: conn} do
      correlation_id = "request-456"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_simulation_request", %{
        "request" => %{
          "graph_id" => "not-a-uuid",
          "correlation_id" => correlation_id,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1
          }
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_id: "not-a-uuid",
        correlation_id: ^correlation_id,
        reason: "invalid_request"
      })
    end

    test "rejects a simulation request without valid parameters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_simulation_request", %{})

      assert_reply(view, %{
        status: "rejected",
        graph_id: "",
        correlation_id: "",
        reason: "invalid_request"
      })
    end

    test "forwards simulation completion and failure events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      completed = %{
        correlation_id: "request-1",
        graph_id: "graph-1",
        experiment_id: "experiment-1"
      }

      send(view.pid, {:simulation_completed, completed})
      assert_push_event(view, "simulation_completed", ^completed)

      failed = %{correlation_id: "request-2", graph_id: "graph-2", reason: "persistence_failed"}

      send(view.pid, {:simulation_failed, failed})
      assert_push_event(view, "simulation_failed", ^failed)
    end
  end

  describe "optimization events" do
    test "accepts an optimization request and persists an optimized graph", %{conn: conn} do
      graph = insert_graph("optimize-test")
      insert_node(graph, "entry-host")
      correlation_id = "optimization-request"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Optimizations.optimization_events_topic())

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_id" => graph.id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{"strategy" => "cvss", "budget" => 1}
        }
      })

      assert_reply(view, %{
        status: "accepted",
        graph_id: graph_id,
        correlation_id: ^correlation_id,
        reason: nil
      })

      assert graph_id == graph.id

      assert_receive {:optimization_completed,
                      %{
                        correlation_id: ^correlation_id,
                        graph_id: ^graph_id,
                        optimized_graph_id: optimized_graph_id
                      }},
                     5_000

      assert %{id: ^optimized_graph_id, parent_id: ^graph_id, source: :optimization} =
               Graphs.load(optimized_graph_id)
    end

    test "rejects invalid optimization parameters", %{conn: conn} do
      graph = insert_graph("invalid-optimization")
      correlation_id = "invalid-optimization-request"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_id" => graph.id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{"strategy" => "cvss", "budget" => 0}
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_id: graph_id,
        correlation_id: ^correlation_id,
        reason: "invalid_request"
      })

      assert graph_id == graph.id
    end

    test "requires simulation parameters for simulation-informed optimization", %{conn: conn} do
      graph = insert_graph("simulation-informed-optimization")
      correlation_id = "simulation-informed-request"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_id" => graph.id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{"strategy" => "simulation_informed", "budget" => 1}
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_id: graph_id,
        correlation_id: ^correlation_id,
        reason: "invalid_request"
      })

      assert graph_id == graph.id
    end

    test "forwards optimization completion and failure events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      completed = %{
        correlation_id: "optimization-1",
        graph_id: "graph-1",
        optimized_graph_id: "optimized-1"
      }

      send(view.pid, {:optimization_completed, completed})
      assert_push_event(view, "optimization_completed", ^completed)

      failed = %{
        correlation_id: "optimization-2",
        graph_id: "graph-2",
        reason: "optimization_failed"
      }

      send(view.pid, {:optimization_failed, failed})
      assert_push_event(view, "optimization_failed", ^failed)
    end
  end

  describe "save_graph" do
    test "persists graph edges and node view_data", %{conn: conn} do
      graph = insert_graph("save-graph")
      source = insert_node(graph, "source")
      target = insert_service(graph, "target")
      edge_id = Ecto.UUID.generate()

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "save_graph", %{
        "graph" => %{
          "id" => graph.id,
          "lock_version" => graph.lock_version,
          "title" => "saved graph",
          "nodes" => [
            %{
              "id" => source.id,
              "type" => "Host",
              "data" => source.data,
              "view_data" => %{"x_pos" => 120, "y_pos" => 240}
            },
            %{
              "id" => target.id,
              "type" => "Service",
              "data" => target.data,
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

      saved_graph = Graphs.load!(graph.id)

      assert [%{from_id: source_id, to_id: target_id, type: type}] = Graph.edges(saved_graph)
      assert source_id == source.id
      assert target_id == target.id
      assert type == NetworkReachability
      assert saved_graph.title == "saved graph"
      assert saved_graph.lock_version == 2

      source_node = Enum.find(saved_graph.nodes, &(&1.id == source.id))
      target_node = Enum.find(saved_graph.nodes, &(&1.id == target.id))
      assert source_node.view_data.x_pos == 120.0
      assert source_node.view_data.y_pos == 240.0
      assert target_node.view_data.x_pos == 360.0
      assert target_node.view_data.y_pos == 480.0
    end

    test "does not replace a stale graph", %{conn: conn} do
      graph = insert_graph("stale-graph")

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "save_graph", %{
        "graph" => %{
          "id" => graph.id,
          "lock_version" => graph.lock_version - 1,
          "title" => "stale graph",
          "nodes" => [],
          "edges" => []
        }
      })

      assert Graphs.load!(graph.id).title == "stale-graph"
    end
  end

  defp insert_graph(title) do
    %Graph{}
    |> Graph.changeset(%{title: title})
    |> Repo.insert!()
  end

  defp insert_node(graph, name) do
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
      data: %{"name" => name, "protocol" => "tcp", "port" => 443},
      view_data: %{"x_pos" => 0, "y_pos" => 0}
    })
    |> Repo.insert!()
  end

  defp insert_edge(source, target) do
    %Edge{graph_id: source.graph_id, from_id: source.id, to_id: target.id}
    |> Edge.changeset(%{type: Atom.to_string(Runs), data: %{}})
    |> Repo.insert!()
  end
end
