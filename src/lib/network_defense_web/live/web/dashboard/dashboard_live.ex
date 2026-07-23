defmodule NetworkDefenseWeb.DashboardLive do
  use NetworkDefenseWeb, :live_view

  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Simulation.Report
  alias NetworkDefense.Simulation.Reports
  alias NetworkDefense.Simulations

  alias NetworkDefenseWeb.Web.Contracts.{
    FetchSimulationReportPayload,
    FetchSimulationReportReply,
    FetchExperimentsPayload,
    FetchExperimentsReply,
    OpenGraphPayload,
    OpenGraphReply,
    OptimizeDefensePayload,
    RunSimulationReply,
    RunSimulationPayload,
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
    case RunSimulationPayload.validate(params) do
      {:ok, %{request: request}} ->
        case Simulations.run_async(request) do
          {:ok, _pid} ->
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
           params |> Map.get("request", %{}) |> Map.get("graph_id"),
           params |> Map.get("request", %{}) |> Map.get("correlation_id"),
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
        case Reports.load_for_report(request.experiment_id) do
          nil ->
            {:reply, %{status: "not_found"}, socket}

          experiment ->
            {:ok, report} = FetchSimulationReportReply.validate(Report.generate(experiment))
            {:reply, FetchSimulationReportReply.to_wire(report), socket}
        end

      {:error, _changeset} ->
        {:reply, %{status: "not_found"}, socket}
    end
  end

  def handle_event("fetch_experiments", params, socket) do
    case FetchExperimentsPayload.validate(params) do
      {:ok, request} ->
        experiments =
          request.graph_ids
          |> Simulations.list_experiments()
          |> Enum.map(fn experiment ->
            %{
              id: experiment.id,
              graph_id: experiment.graph_id,
              graph_title: (experiment.graph && experiment.graph.title) || "Unknown",
              seed: experiment.seed,
              run_count: experiment.run_count || 0,
              iteration_count: experiment.iteration_count,
              runtime_ms: experiment.runtime_ms,
              started_at: experiment.inserted_at && DateTime.to_iso8601(experiment.inserted_at)
            }
          end)

        {:ok, reply} = FetchExperimentsReply.validate(%{experiments: experiments})
        {:reply, FetchExperimentsReply.to_wire(reply), socket}

      {:error, _changeset} ->
        {:reply, FetchExperimentsReply.to_wire(%FetchExperimentsReply{experiments: []}), socket}
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

  defp open_graph(params) do
    case OpenGraphPayload.validate(params) do
      {:ok, request} -> graph_open_reply(Graphs.load(request.graph_id))
      {:error, _changeset} -> open_graph_reply("invalid_graph")
    end
  end

  defp graph_open_reply(nil), do: open_graph_reply("not_found")

  defp graph_open_reply(graph) do
    case GraphContract.from_domain(graph) do
      {:ok, wire_graph} -> open_graph_reply("ok", wire_graph)
      {:error, _changeset} -> open_graph_reply("unmapped_error")
    end
  end

  defp save_graph(graph, socket) do
    case Graphs.replace(graph) do
      {:ok, %{graph: persisted}} -> save_graph_success(persisted, socket)
      {:error, reason} -> {:reply, save_graph_reply(save_error_status(reason)), socket}
    end
  end

  defp save_graph_success(persisted, socket) do
    case GraphContract.from_domain(persisted) do
      {:ok, wire_graph} ->
        {:reply, save_graph_reply("ok", wire_graph),
         assign(socket, :graph_summaries, Graphs.list_summaries())}

      {:error, _changeset} ->
        {:reply, save_graph_reply("unmapped_error"), socket}
    end
  end

  defp save_error_status(:stale), do: "stale"
  defp save_error_status(:not_found), do: "not_found"
  defp save_error_status(:invalid_graph), do: "invalid_graph"
  defp save_error_status(_reason), do: "unmapped_error"

  defp simulation_request_reply(status, graph_id, correlation_id, reason) do
    contract_reply(RunSimulationReply, %{
      status: status,
      graph_id: string_or_empty(graph_id),
      correlation_id: string_or_empty(correlation_id),
      reason: reason
    })
  end

  defp string_or_empty(value) when is_binary(value), do: value
  defp string_or_empty(_value), do: ""

  defp open_graph_reply(status, graph \\ nil) do
    contract_reply(OpenGraphReply, %{status: status, graph: graph})
  end

  defp save_graph_reply(status, graph \\ nil) do
    contract_reply(SaveGraphReply, %{status: status, graph: graph})
  end

  defp contract_reply(contract, attrs) do
    {:ok, reply} = contract.validate(attrs)
    contract.to_wire(reply)
  end

  defp push_contract_event(socket, event, contract, payload) do
    case contract.validate(payload) do
      {:ok, event_payload} -> push_event(socket, event, contract.to_wire(event_payload))
      {:error, _changeset} -> socket
    end
  end
end
