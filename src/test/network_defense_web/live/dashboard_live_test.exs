defmodule NetworkDefenseWeb.DashboardLiveTest do
  use NetworkDefenseWeb.ConnCase

  import Phoenix.LiveViewTest

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Repo
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Runs
  alias NetworkDefense.Nodes.Host

  describe "mount" do
    test "renders the Svelte dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#dashboard[data-name='Dashboard']")
    end
  end

  describe "open_topology" do
    test "is handled for an existing graph", %{conn: conn} do
      graph = insert_graph("dwg-001")
      source = insert_node(graph, "origin")
      target = insert_node(graph, "dest")
      insert_edge(source, target)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "open_topology", %{"graph_id" => graph.id})

      assert has_element?(view, "#dashboard[data-name='Dashboard']")
    end

    test "is safely ignored for an invalid graph_id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "open_topology", %{"graph_id" => "00000000-0000-0000-0000-000000000000"})

      assert has_element?(view, "#dashboard[data-name='Dashboard']")
    end

    test "is safely ignored without graph_id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "open_topology", %{})

      assert has_element?(view, "#dashboard[data-name='Dashboard']")
    end
  end

  describe "existing events" do
    test "dashboard root is present after run_simulation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "run_simulation", %{"graph_id" => "topology-1"})

      assert has_element?(view, "#dashboard[data-name='Dashboard']")
    end

    test "dashboard root is present after optimize_defense", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "optimize_defense", %{"graph_id" => "topology-1"})

      assert has_element?(view, "#dashboard[data-name='Dashboard']")
    end

    test "run_simulation is safely accepted without graph_id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "run_simulation", %{})

      assert has_element?(view, "#dashboard[data-name='Dashboard']")
    end

    test "optimize_defense is safely accepted without graph_id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "optimize_defense", %{})

      assert has_element?(view, "#dashboard[data-name='Dashboard']")
    end
  end

  describe "save_topology" do
    test "persists topology edges and positions", %{conn: conn} do
      graph = insert_graph("save-topology")
      source = insert_node(graph, "source")
      target = insert_node(graph, "target")
      edge_id = Ecto.UUID.generate()

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "save_topology", %{
        "graph_id" => graph.id,
        "lock_version" => graph.lock_version,
        "title" => "saved topology",
        "nodes" => [
          %{"id" => source.id, "type" => source.type, "data" => source.data},
          %{"id" => target.id, "type" => target.type, "data" => target.data}
        ],
        "edges" => [
          %{
            "id" => edge_id,
            "from_id" => source.id,
            "to_id" => target.id,
            "type" => Atom.to_string(NetworkReachability),
            "data" => %{}
          }
        ],
        "positions" => %{
          source.id => %{"x" => 120, "y" => 240},
          target.id => %{"x" => 360, "y" => 480}
        }
      })

      saved_graph = Graphs.load!(graph.id)

      assert [%{from_id: source_id, to_id: target_id, type: type}] = Graph.edges(saved_graph)
      assert source_id == source.id
      assert target_id == target.id
      assert type == Atom.to_string(NetworkReachability)
      assert saved_graph.title == "saved topology"
      assert saved_graph.lock_version == 2

      assert saved_graph.positions == %{
               source.id => %{"x" => 120, "y" => 240},
               target.id => %{"x" => 360, "y" => 480}
             }
    end
  end

  defp insert_graph(title) do
    %Graph{}
    |> Graph.changeset(%{title: title})
    |> Repo.insert!()
  end

  defp insert_node(graph, name) do
    %Node{graph_id: graph.id}
    |> Node.changeset(%{type: Atom.to_string(Host), data: %{"name" => name}})
    |> Repo.insert!()
  end

  defp insert_edge(source, target) do
    %Edge{graph_id: source.graph_id, from_id: source.id, to_id: target.id}
    |> Edge.changeset(%{type: Atom.to_string(Runs)})
    |> Repo.insert!()
  end
end
