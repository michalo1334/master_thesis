defmodule NetworkDefenseWeb.DashboardLive do
  alias NetworkDefense.Graph.GraphLayout
  use NetworkDefenseWeb, :live_view

  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Graphs

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
  def handle_event("open_topology", %{"graph_id" => graph_id}, socket) when is_binary(graph_id) do
    case Graphs.load(graph_id) do
      nil ->
        {:reply, %{topology: nil}, socket}

      graph ->
        {:reply, %{topology: graph |> GraphLayout.lay_out(:none) |> graph_payload()}, socket}
    end
  end

  def handle_event("open_topology", _params, socket) do
    {:reply, %{topology: nil}, socket}
  end

  @impl true
  def handle_event(
        "save_topology",
        %{
          "graph_id" => graph_id,
          "lock_version" => lock_version,
          "title" => title,
          "nodes" => nodes,
          "edges" => edges,
          "positions" => positions
        },
        socket
      ) do
    attrs = %{"title" => title, "nodes" => nodes, "edges" => edges, "positions" => positions}

    case Graphs.replace(graph_id, lock_version, attrs) do
      {:ok, %{graph: graph}} ->
        {:reply,
         %{status: "ok", topology: graph |> GraphLayout.lay_out(:none) |> graph_payload()},
         assign(socket, :graph_summaries, Graphs.list_summaries())}

      {:error, :stale} ->
        {:reply, %{status: "stale"}, socket}

      {:error, :not_found} ->
        {:reply, %{status: "not_found"}, socket}

      {:error, _reason} ->
        {:reply, %{status: "error"}, socket}
    end
  end

  def handle_event("save_topology", _params, socket) do
    {:reply, %{status: "error"}, socket}
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
      title: graph.title,
      id: graph.id,
      lockVersion: graph.lock_version,
      positions: graph.positions,
      nodes:
        Enum.map(Graph.nodes(graph), fn node ->
          %{
            id: node.id,
            graphId: graph.id,
            type: node.type,
            data: node.data
          }
        end),
      edges:
        Enum.map(Graph.edges(graph), fn edge ->
          %{
            id: edge.id,
            graphId: graph.id,
            fromId: edge.from_id,
            toId: edge.to_id,
            type: edge.type,
            data: edge.data
          }
        end)
    }
  end
end
