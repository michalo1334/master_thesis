defmodule NetworkDefenseWeb.DashboardLive do
  alias NetworkDefense.Graph.GraphLayout
  use NetworkDefenseWeb, :live_view

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Graph.Node
  alias NetworkDefenseWeb.Web.Contracts.LayoutGraph.LayoutParams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full_screen>
      <.svelte
        name="Dashboard"
        id="dashboard"
        props={
          %{
            graphSummaries: @graph_summaries
          }
        }
        socket={@socket}
      />
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:graph_summaries, Graphs.list_summaries())

    {:ok, socket}
  end

  @impl true
  def handle_event("open_graph", %{"graph_id" => graph_id}, socket) when is_binary(graph_id) do
    case Graphs.load(graph_id) do
      nil ->
        {:reply, %{status: "not_found", graph: nil}, socket}

      graph ->
        {:reply, %{status: "ok", graph: graph_payload(graph)}, socket}
    end
  end

  def handle_event("open_graph", _params, socket) do
    {:reply, %{status: "not_found", graph: nil}, socket}
  end

  @impl true
  def handle_event(
        "save_graph",
        %{
          "graph" => %{
            "id" => graph_id,
            "lock_version" => lock_version,
            "title" => title,
            "nodes" => nodes,
            "edges" => edges
          }
        },
        socket
      ) do
    attrs = %{"title" => title, "nodes" => nodes, "edges" => edges}

    case Graphs.replace(graph_id, lock_version, attrs) do
      {:ok, %{graph: graph}} ->
        {:reply,
         %{status: "ok", graph: graph_payload(GraphLayout.lay_out(:force_directed, graph))},
         assign(socket, :graph_summaries, Graphs.list_summaries())}

      {:error, :stale} ->
        {:reply, %{status: "stale", graph: nil}, socket}

      {:error, :not_found} ->
        {:reply, %{status: "not_found", graph: nil}, socket}

      {:error, _reason} ->
        {:reply, %{status: "unmapped_error", graph: nil}, socket}
    end
  end

  def handle_event("save_graph", _params, socket) do
    {:reply, %{status: "unmapped_error", graph: nil}, socket}
  end

  @impl true
  def handle_event(
        "layout_graph",
        %{
          "graph" => %{
            "id" => id,
            "title" => title,
            "lock_version" => lock_version,
            "nodes" => nodes,
            "edges" => edges
          },
          "params" => raw_params
        },
        socket
      ) do
    lp = LayoutParams.new(raw_params)
    graph = build_graph_from_payload(nodes, edges)

    opts = [
      iteration: lp.iterations,
      preferred_edge_length: lp.spring_length,
      repulsion_strength: lp.repulsion
    ]

    result = GraphLayout.lay_out(:force_directed, graph, opts)
    positions = Map.new(Graph.nodes(result), &{&1.id, Node.position(&1)})

    updated_nodes =
      Enum.map(nodes, fn node ->
        {x, y} = Map.fetch!(positions, node["id"])
        Map.put(node, "view_data", %{"x_pos" => x, "y_pos" => y})
      end)

    {:reply,
     %{
       status: "ok",
       graph: %{
         id: id,
         title: title,
         lock_version: lock_version,
         nodes: updated_nodes,
         edges: edges
       }
     }, socket}
  end

  def handle_event("layout_graph", params, socket) do
    if is_map(params) and Map.has_key?(params, "params") do
      {:reply, %{status: "unmapped_error", graph: nil}, socket}
    else
      {:reply, %{status: "unmapped_error", graph: nil}, socket}
    end
  end

  @impl true
  def handle_event("run_simulation", %{"graph_id" => graph_id}, socket)
      when is_binary(graph_id) and byte_size(graph_id) > 0 do
    {:noreply, socket}
  end

  def handle_event("run_simulation", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("optimize_defense", %{"graph_id" => graph_id}, socket)
      when is_binary(graph_id) and byte_size(graph_id) > 0 do
    {:noreply, socket}
  end

  def handle_event("optimize_defense", _params, socket) do
    {:noreply, socket}
  end

  defp graph_payload(graph) do
    %{
      id: graph.id,
      title: graph.title,
      lock_version: graph.lock_version,
      nodes:
        Enum.map(Graph.nodes(graph), fn node ->
          %{
            id: node.id,
            type: type(node.type),
            data: node.data,
            view_data: %{
              x_pos: Map.get(node.view_data, :x_pos) || Map.get(node.view_data, "x_pos"),
              y_pos: Map.get(node.view_data, :y_pos) || Map.get(node.view_data, "y_pos")
            }
          }
        end),
      edges:
        Enum.map(Graph.edges(graph), fn edge ->
          %{
            id: edge.id,
            from_id: edge.from_id,
            to_id: edge.to_id,
            type: type(edge.type),
            data: edge.data
          }
        end)
    }
  end

  defp type(module), do: module |> Module.split() |> List.last()

  defp build_graph_from_payload(nodes, edges) do
    graph = Graph.new("layout_temp")

    node_structs =
      Enum.map(nodes, fn %{
                           "id" => id,
                           "type" => type,
                           "data" => data,
                           "view_data" => %{"x_pos" => x_pos, "y_pos" => y_pos}
                         } ->
        full_type = "Elixir.NetworkDefense.Nodes.#{type}"

        struct!(Node,
          id: id,
          graph_id: graph.id,
          type: full_type,
          data: data || %{},
          view_data: %{"x_pos" => x_pos, "y_pos" => y_pos}
        )
      end)

    graph =
      Enum.reduce(node_structs, graph, fn node, acc ->
        Graph.add_node(acc, node)
      end)

    Enum.reduce(edges, graph, fn %{
                                   "id" => id,
                                   "from_id" => from_id,
                                   "to_id" => to_id,
                                   "type" => type,
                                   "data" => data
                                 },
                                 acc ->
      full_type = "Elixir.NetworkDefense.Relationships.#{type}"

      edge =
        struct!(Edge,
          id: id,
          graph_id: graph.id,
          from_id: from_id,
          to_id: to_id,
          type: full_type,
          data: data || %{}
        )

      Graph.add_edge(acc, edge)
    end)
  end
end
