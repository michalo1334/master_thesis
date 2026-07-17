defmodule NetworkDefenseWeb.DashboardLive do
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
            graphSummaries: @graph_summaries,
            selectedGraph: @selected_graph,
            selectedGraphRequestId: @open_request_seq
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
      |> assign(:selected_graph, nil)
      |> assign(:open_request_seq, 0)

    {:ok, socket}
  end

  @impl true
  def handle_event("open_topology", %{"graph_id" => graph_id}, socket) when is_binary(graph_id) do
    socket =
      case Graphs.load(graph_id) do
        nil ->
          socket

        graph ->
          seq = socket.assigns.open_request_seq + 1

          nodes =
            Enum.map(Graph.nodes(graph), fn node ->
              %{
                id: node.id,
                graphId: graph.id,
                type: node.type,
                data: node.data
              }
            end)

          edges =
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

          selected_graph = %{
            title: graph.title,
            id: graph.id,
            nodes: nodes,
            edges: edges
          }

          assign(socket, :selected_graph, selected_graph)
          |> assign(:open_request_seq, seq)
      end

    {:noreply, socket}
  end

  def handle_event("open_topology", _params, socket) do
    {:noreply, socket}
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
end
