defmodule NetworkDefenseWeb.DashboardLiveTest do
  use NetworkDefenseWeb.ConnCase

  import Phoenix.LiveViewTest

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Repo
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Runs
  alias NetworkDefense.Simulation.Contracts.SimulationParams
  alias NetworkDefense.Simulations
  alias NetworkDefenseWeb.DashboardLive

  describe "mount" do
    test "renders the Svelte dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end
  end

  describe "open_graph" do
    test "accepts an existing graph", %{conn: conn} do
      graph = insert_graph("dwg-001")
      source = insert_node(graph, "origin")
      target = insert_node(graph, "dest")
      insert_edge(source, target)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "open_graph", %{"graph_id" => graph.id})

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end

    test "accepts a missing graph_id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "open_graph", %{
        "graph_id" => "00000000-0000-0000-0000-000000000000"
      })

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end

    test "accepts an open request without graph_id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "open_graph", %{})

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end
  end

  describe "simulation events" do
    test "accepts a correlated simulation request and broadcasts its completion", %{conn: conn} do
      graph = insert_graph("run-sim-test")
      graph_id = graph.id
      correlation_id = "request-123"

      {:ok, view, _html} = live(conn, ~p"/dashboard")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

      assert {:reply,
              %{
                status: "accepted",
                graph_id: ^graph_id,
                correlation_id: ^correlation_id,
                reason: nil
              }, _socket} =
               DashboardLive.handle_event(
                 "run_simulation_request",
                 %{
                   "request" => %{
                     "graph_id" => graph_id,
                     "correlation_id" => correlation_id,
                     "simulation_params" => %{
                       "monte_carlo_trials" => 1,
                       "iterations_per_run" => 1
                     }
                   }
                 },
                 %Phoenix.LiveView.Socket{}
               )

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

    test "dashboard root is present after optimize_defense", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "optimize_defense", %{"graph_id" => "topology-1"})

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end

    test "rejects an invalid correlated simulation request" do
      correlation_id = "request-456"

      assert {:reply,
              %{
                status: "rejected",
                graph_id: "not-a-uuid",
                correlation_id: ^correlation_id,
                reason: "invalid_request"
              }, _socket} =
               DashboardLive.handle_event(
                 "run_simulation_request",
                 %{
                   "request" => %{
                     "graph_id" => "not-a-uuid",
                     "correlation_id" => correlation_id,
                     "simulation_params" => %{
                       "monte_carlo_trials" => 1,
                       "iterations_per_run" => 1
                     }
                   }
                 },
                 %Phoenix.LiveView.Socket{}
               )
    end

    test "rejects a simulation request without valid parameters" do
      assert {:reply,
              %{
                status: "rejected",
                graph_id: "",
                correlation_id: "",
                reason: "invalid_request"
              }, _socket} =
               DashboardLive.handle_event(
                 "run_simulation_request",
                 %{},
                 %Phoenix.LiveView.Socket{}
               )
    end

    test "broadcasts a correlated failure when execution fails" do
      graph = %{Graph.new("invalid graph") | nodes: [%Node{type: nil}]}
      graph_id = graph.id
      correlation_id = "request-789"

      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

      assert {:ok, _pid} =
               Simulations.run_async(graph, correlation_id, %SimulationParams{
                 monte_carlo_trials: 1,
                 iterations_per_run: 1
               })

      assert_receive {:simulation_failed,
                      %{
                        correlation_id: ^correlation_id,
                        graph_id: ^graph_id,
                        reason: reason
                      }},
                     5_000

      assert is_binary(reason)
    end

    test "forwards simulation completion and failure events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

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

    test "optimize_defense is safely accepted without graph_id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "optimize_defense", %{})

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end
  end

  describe "save_graph" do
    test "persists graph edges and node view_data", %{conn: conn} do
      graph = insert_graph("save-graph")
      source = insert_node(graph, "source")
      target = insert_node(graph, "target")
      edge_id = Ecto.UUID.generate()

      {:ok, view, _html} = live(conn, ~p"/dashboard")

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
              "type" => "Host",
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
              "data" => %{}
            }
          ]
        }
      })

      saved_graph = Graphs.load!(graph.id)

      assert [%{from_id: source_id, to_id: target_id, type: type}] = Graph.edges(saved_graph)
      assert source_id == source.id
      assert target_id == target.id
      assert type == Atom.to_string(NetworkReachability)
      assert saved_graph.title == "saved graph"
      assert saved_graph.lock_version == 2

      source_node = Enum.find(saved_graph.nodes, &(&1.id == source.id))
      target_node = Enum.find(saved_graph.nodes, &(&1.id == target.id))
      assert source_node.view_data == %{"x_pos" => 120.0, "y_pos" => 240.0}
      assert target_node.view_data == %{"x_pos" => 360.0, "y_pos" => 480.0}
    end

    test "does not replace a stale graph", %{conn: conn} do
      graph = insert_graph("stale-graph")

      {:ok, view, _html} = live(conn, ~p"/dashboard")

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

  defp insert_edge(source, target) do
    %Edge{graph_id: source.graph_id, from_id: source.id, to_id: target.id}
    |> Edge.changeset(%{type: Atom.to_string(Runs)})
    |> Repo.insert!()
  end
end
