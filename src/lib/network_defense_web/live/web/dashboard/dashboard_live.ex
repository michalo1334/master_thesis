defmodule NetworkDefenseWeb.DashboardLive do
  use NetworkDefenseWeb, :live_view

  require Logger

  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Simulation.Reports
  alias NetworkDefense.Simulation.Report
  alias NetworkDefense.Simulations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full_screen>
      <.svelte
        name="DashboardHost"
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

    if connected?(socket) do
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())
    end

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
    Logger.debug(%{
      save_graph: :entry,
      graph_id: graph_id,
      lock_version: lock_version,
      title: title,
      nodes: nodes,
      edges: edges
    })

    attrs = %{"title" => title, "nodes" => nodes, "edges" => edges}

    case Graphs.replace(graph_id, lock_version, attrs) do
      {:ok, %{graph: graph}} ->
        {:reply, %{status: "ok", graph: graph_payload(graph)},
         assign(socket, :graph_summaries, Graphs.list_summaries())}

      {:error, :stale} ->
        {:reply, %{status: "stale", graph: nil}, socket}

      {:error, :not_found} ->
        {:reply, %{status: "not_found", graph: nil}, socket}

      {:error, :invalid_graph} ->
        {:reply, %{status: "invalid_graph", graph: nil}, socket}

      {:error, _reason} ->
        {:reply, %{status: "unmapped_error", graph: nil}, socket}
    end
  end

  def handle_event("save_graph", _params, socket) do
    {:reply, %{status: "unmapped_error", graph: nil}, socket}
  end

  @impl true
  def handle_event(
        "run_simulation_request",
        %{"graph_id" => graph_id, "correlation_id" => correlation_id},
        socket
      )
      when is_binary(graph_id) and byte_size(graph_id) > 0 and is_binary(correlation_id) and
             byte_size(correlation_id) > 0 do
    case load_simulation_graph(graph_id) do
      {:ok, graph} ->
        {:ok, _pid} = Simulations.run_async(graph, correlation_id)
        {:reply, simulation_request_reply("accepted", graph_id, correlation_id, nil), socket}

      {:error, reason} ->
        {:reply, simulation_request_reply("rejected", graph_id, correlation_id, reason), socket}
    end
  end

  def handle_event("run_simulation_request", params, socket) do
    {:reply,
     simulation_request_reply(
       "rejected",
       Map.get(params, "graph_id"),
       Map.get(params, "correlation_id"),
       "invalid_request"
     ), socket}
  end

  @impl true
  def handle_event("optimize_defense", %{"graph_id" => graph_id}, socket)
      when is_binary(graph_id) and byte_size(graph_id) > 0 do
    {:noreply, socket}
  end

  def handle_event("optimize_defense", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("fetch_simulation_report", %{"multi_state_id" => multi_state_id}, socket) do
    case Reports.load_for_report(multi_state_id) do
      nil ->
        {:reply, %{status: "not_found"}, socket}

      multi_state ->
        report = Report.generate(multi_state)
        {:reply, report, socket}
    end
  end

  def handle_event("fetch_simulation_runs", %{"graph_ids" => graph_ids}, socket)
      when is_list(graph_ids) do
    runs =
      graph_ids
      |> Simulations.list_runs()
      |> Enum.map(fn ms ->
        %{
          id: ms.id,
          graph_id: ms.graph_id,
          graph_title: (ms.graph && ms.graph.title) || "Unknown",
          seed: ms.seed,
          simulation_count: ms.simulation_count || 0,
          iteration_count: ms.iteration_count,
          runtime_ms: ms.runtime_ms,
          started_at: ms.inserted_at && DateTime.to_iso8601(ms.inserted_at)
        }
      end)

    {:reply, %{runs: runs}, socket}
  end

  def handle_event("fetch_simulation_runs", _params, socket) do
    {:reply, %{runs: []}, socket}
  end

  @impl true
  def handle_info({:simulation_completed, payload}, socket) do
    {:noreply, push_event(socket, "simulation_completed", payload)}
  end

  def handle_info({:simulation_failed, payload}, socket) do
    {:noreply, push_event(socket, "simulation_failed", payload)}
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
              y_pos: Map.get(node.view_data, :y_pos) || Map.get(node.view_data, "y_pos"),
              radius: Map.get(node.view_data, :radius) || Map.get(node.view_data, "radius")
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

  defp load_simulation_graph(graph_id) do
    with {:ok, graph_id} <- Ecto.UUID.cast(graph_id),
         graph when not is_nil(graph) <- Graphs.load(graph_id) do
      {:ok, graph}
    else
      :error -> {:error, "invalid_graph_id"}
      nil -> {:error, "graph_not_found"}
    end
  end

  defp simulation_request_reply(status, graph_id, correlation_id, reason) do
    %{
      status: status,
      graph_id: string_or_empty(graph_id),
      correlation_id: string_or_empty(correlation_id),
      reason: reason
    }
  end

  defp string_or_empty(value) when is_binary(value), do: value
  defp string_or_empty(_value), do: ""
end
