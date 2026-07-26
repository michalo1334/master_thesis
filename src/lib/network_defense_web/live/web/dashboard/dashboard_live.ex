defmodule NetworkDefenseWeb.DashboardLive do
  use NetworkDefenseWeb, :live_view

  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Simulations
  alias OpentelemetryProcessPropagator.Task.Supervisor, as: TaskSupervisor

  alias NetworkDefenseWeb.Web.Contracts.{
    FetchSimulationReportPayload,
    FetchSimulationReportReply,
    FetchExperimentsPayload,
    FetchExperimentsReply,
    OpenGraphPayload,
    OpenGraphReply,
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
  def handle_event("fetch_simulation_report", params, socket) do
    case FetchSimulationReportPayload.validate(params) do
      {:ok, request} ->
        case start_report_fetch(request, params, self()) do
          {:ok, _pid} -> {:reply, %{status: "processing"}, socket}
          {:error, _reason} -> {:reply, %{status: "unavailable"}, socket}
        end

      {:error, _changeset} ->
        {:reply, %{status: "invalid_params"}, socket}
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

  def handle_info({:report_result, experiment_id, graph_id, result}, socket) do
    socket =
      if is_map(result) and result[:charts] do
        push_event(socket, "simulation_report_ready", result)
      else
        push_event(socket, "simulation_report_error", %{
          experiment_id: experiment_id,
          graph_id: graph_id,
          reason: (is_map(result) && result[:status]) || "unknown_error"
        })
      end

    {:noreply, socket}
  end

  defp fetch_simulation_report(params) do
    case FetchSimulationReportPayload.validate(params) do
      {:ok, request} ->
        with %{} = report <- Simulations.get_report(request.experiment_id),
             {:ok, report} <- FetchSimulationReportReply.from_domain(report) do
          FetchSimulationReportReply.to_wire(report)
        else
          _ -> %{status: "not_found"}
        end

      {:error, _changeset} ->
        %{status: "not_found"}
    end
  end

  defp start_report_fetch(request, params, owner) do
    TaskSupervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
      send(
        owner,
        {:report_result, request.experiment_id, request.graph_id, report_result(params)}
      )
    end)
  end

  defp report_result(params) do
    fetch_simulation_report(params)
  rescue
    e -> %{status: "crash: #{Exception.message(e)}"}
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
