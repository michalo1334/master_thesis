defmodule NetworkDefenseWeb.DashboardLive do
  use NetworkDefenseWeb, :live_view

  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Simulation.Report
  alias NetworkDefense.Simulation.Reports
  alias NetworkDefense.Simulations
  alias NetworkDefenseWeb.Web.Contracts

  alias NetworkDefenseWeb.Web.Contracts.{
    FetchSimulationReportPayload,
    FetchSimulationReportReply,
    FetchSimulationRunsPayload,
    FetchSimulationRunsReply,
    GraphContract,
    OpenGraphPayload,
    OpenGraphReply,
    OptimizeDefensePayload,
    RunSimulationReply,
    RunSimulationRequest,
    SaveGraphPayload,
    SaveGraphReply,
    SimulationCompletedEvent,
    SimulationFailedEvent
  }

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
  def handle_event("open_graph", params, socket) do
    {:reply, open_graph(params), socket}
  end

  @impl true
  def handle_event("save_graph", params, socket) do
    case SaveGraphPayload.validate(params) do
      {:ok, %{graph: graph}} ->
        save_graph(graph, socket)

      {:error, _changeset} ->
        {:reply, save_graph_reply("invalid_graph"), socket}
    end
  end

  @impl true
  def handle_event("run_simulation_request", params, socket) do
    case RunSimulationRequest.validate(params) do
      {:ok, request} ->
        case load_simulation_graph(request.graph_id) do
          {:ok, graph} ->
            {:ok, _pid} =
              Simulations.run_async(graph, request.correlation_id, request.simulation_params)

            {:reply,
             simulation_request_reply("accepted", request.graph_id, request.correlation_id, nil),
             socket}

          {:error, reason} ->
            {:reply,
             simulation_request_reply(
               "rejected",
               request.graph_id,
               request.correlation_id,
               reason
             ), socket}
        end

      {:error, _changeset} ->
        {:reply,
         simulation_request_reply(
           "rejected",
           Map.get(params, "graph_id"),
           Map.get(params, "correlation_id"),
           "invalid_request"
         ), socket}
    end
  end

  @impl true
  def handle_event("optimize_defense", params, socket) do
    _ = OptimizeDefensePayload.validate(params)
    {:noreply, socket}
  end

  @impl true
  def handle_event("fetch_simulation_report", params, socket) do
    case FetchSimulationReportPayload.validate(params) do
      {:ok, request} ->
        case Reports.load_for_report(request.multi_state_id) do
          nil ->
            {:reply, %{status: "not_found"}, socket}

          multi_state ->
            {:ok, report} = FetchSimulationReportReply.validate(Report.generate(multi_state))
            {:reply, FetchSimulationReportReply.to_wire(report), socket}
        end

      {:error, _changeset} ->
        {:reply, %{status: "not_found"}, socket}
    end
  end

  def handle_event("fetch_simulation_runs", params, socket) do
    case FetchSimulationRunsPayload.validate(params) do
      {:ok, request} ->
        runs =
          request.graph_ids
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

        {:ok, reply} = FetchSimulationRunsReply.validate(%{runs: runs})
        {:reply, FetchSimulationRunsReply.to_wire(reply), socket}

      {:error, _changeset} ->
        {:reply, FetchSimulationRunsReply.to_wire(%FetchSimulationRunsReply{runs: []}), socket}
    end
  end

  @impl true
  def handle_info({:simulation_completed, payload}, socket) do
    {:noreply,
     push_contract_event(socket, "simulation_completed", SimulationCompletedEvent, payload)}
  end

  def handle_info({:simulation_failed, payload}, socket) do
    {:noreply, push_contract_event(socket, "simulation_failed", SimulationFailedEvent, payload)}
  end

  defp graph_contract(graph) do
    GraphContract.validate(%{
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
    })
  end

  defp open_graph(params) do
    case OpenGraphPayload.validate(params) do
      {:ok, request} -> graph_open_reply(Graphs.load(request.graph_id))
      {:error, _changeset} -> open_graph_reply("not_found")
    end
  end

  defp graph_open_reply(nil), do: open_graph_reply("not_found")

  defp graph_open_reply(graph) do
    case graph_contract(graph) do
      {:ok, contract} -> open_graph_reply("ok", contract)
      {:error, _changeset} -> open_graph_reply("unmapped_error")
    end
  end

  defp save_graph(graph, socket) do
    case Graphs.replace(graph.id, graph.lock_version, graph_attrs(graph)) do
      {:ok, %{graph: persisted}} -> save_graph_success(persisted, socket)
      {:error, reason} -> {:reply, save_graph_reply(save_error_status(reason)), socket}
    end
  end

  defp save_graph_success(persisted, socket) do
    case graph_contract(persisted) do
      {:ok, contract} ->
        {:reply, save_graph_reply("ok", contract),
         assign(socket, :graph_summaries, Graphs.list_summaries())}

      {:error, _changeset} ->
        {:reply, save_graph_reply("unmapped_error"), socket}
    end
  end

  defp save_error_status(:stale), do: "stale"
  defp save_error_status(:not_found), do: "not_found"
  defp save_error_status(:invalid_graph), do: "invalid_graph"
  defp save_error_status(_reason), do: "unmapped_error"

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
    {:ok, reply} =
      RunSimulationReply.validate(%{
        status: status,
        graph_id: string_or_empty(graph_id),
        correlation_id: string_or_empty(correlation_id),
        reason: reason
      })

    RunSimulationReply.to_wire(reply)
  end

  defp string_or_empty(value) when is_binary(value), do: value
  defp string_or_empty(_value), do: ""

  defp graph_attrs(graph) do
    %{
      "title" => graph.title,
      "nodes" => Enum.map(graph.nodes, &node_attrs/1),
      "edges" => Enum.map(graph.edges, &edge_attrs/1)
    }
  end

  defp node_attrs(node) do
    %{
      "id" => node.id,
      "type" => node.type,
      "data" => Contracts.to_params(node.data),
      "view_data" =>
        node.view_data
        |> Contracts.to_params()
        |> Map.reject(fn {_key, value} -> is_nil(value) end)
    }
  end

  defp edge_attrs(edge) do
    %{
      "id" => edge.id,
      "from_id" => edge.from_id,
      "to_id" => edge.to_id,
      "type" => edge.type,
      "data" => Contracts.to_params(edge.data)
    }
  end

  defp open_graph_reply(status, graph \\ nil) do
    {:ok, reply} =
      OpenGraphReply.validate(%{status: status, graph: graph && GraphContract.to_wire(graph)})

    OpenGraphReply.to_wire(reply)
  end

  defp save_graph_reply(status, graph \\ nil) do
    {:ok, reply} =
      SaveGraphReply.validate(%{status: status, graph: graph && GraphContract.to_wire(graph)})

    SaveGraphReply.to_wire(reply)
  end

  defp push_contract_event(socket, event, contract, payload) do
    case contract.validate(payload) do
      {:ok, event_payload} -> push_event(socket, event, contract.to_wire(event_payload))
      {:error, _changeset} -> socket
    end
  end
end
