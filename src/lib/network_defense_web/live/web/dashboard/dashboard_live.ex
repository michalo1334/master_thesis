defmodule NetworkDefenseWeb.DashboardLive do
  use NetworkDefenseWeb, :live_view

  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefense.Graph.{Edge, Graphs, Node}
  alias NetworkDefense.Graph.SemanticConnectivity
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Simulations
  alias OpentelemetryProcessPropagator.Task.Supervisor, as: TaskSupervisor

  alias NetworkDefenseWeb.Web.Contracts.{
    FetchSimulationReportPayload,
    FetchSimulationReportReply,
    FetchExperimentsPayload,
    FetchExperimentsReply,
    CreateConnectionDraftPayload,
    CreateConnectionDraftReply,
    CreateNodeDraftPayload,
    CreateNodeDraftReply,
    GraphConnectivityReply,
    OpenGraphPayload,
    OpenGraphReply,
    GraphSummary,
    OptimizationCompletedEvent,
    OptimizationFailedEvent,
    OptimizationProgressEvent,
    RunOptimizationPayload,
    RunOptimizationReply,
    RunSimulationReply,
    RunSimulationPayload,
    SaveGraphPayload,
    SaveGraphReply,
    SimulationCompletedEvent,
    SimulationFailedEvent,
    SimulationProgressEvent,
    SimulationReportErrorEvent
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
      |> assign(:graph_summaries, graph_summaries())

    if connected?(socket) do
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Optimizations.optimization_events_topic())
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
  def handle_event("fetch_graph_connectivity", _params, socket) do
    {:reply, graph_connectivity_reply(), socket}
  end

  @impl true
  def handle_event("create_node_draft", params, socket) do
    reply =
      with {:ok, payload} <- CreateNodeDraftPayload.validate(params),
           {:ok, node} <-
             Node.draft(payload.node_type, %{x_pos: payload.x_pos, y_pos: payload.y_pos}) do
        node_draft_reply("ok", node)
      else
        _ -> node_draft_reply("invalid")
      end

    {:reply, reply, socket}
  end

  @impl true
  def handle_event("create_connection_draft", params, socket) do
    reply =
      with {:ok, payload} <- CreateConnectionDraftPayload.validate(params),
           {:ok, node, target} <- connection_target(payload),
           source = %{id: payload.source_id, type: payload.source_type},
           {from, to} <- if(payload.source_is_from, do: {source, target}, else: {target, source}),
           {:ok, edge} <- Edge.draft(payload.relationship_type, from, to) do
        connection_draft_reply("ok", node, edge)
      else
        _ -> connection_draft_reply("invalid")
      end

    {:reply, reply, socket}
  end

  @impl true
  def handle_event("run_simulation_request", params, socket) do
    case RunSimulationPayload.validate(params) do
      {:ok, %{request: request}} ->
        case Simulations.run_async(request) do
          {:ok, _pid} ->
            {:reply,
             simulation_request_reply("accepted", request.graph_id, request.correlation_id, nil),
             put_flash(socket, :info, "Simulation started.")}

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
  def handle_event("run_optimization_request", params, socket) do
    case RunOptimizationPayload.validate(params) do
      {:ok, %{request: request}} ->
        case Optimizations.run_async(request) do
          {:ok, _pid} ->
            {:reply,
             optimization_request_reply(
               "accepted",
               request.graph_id,
               request.correlation_id,
               nil
             ), put_flash(socket, :info, "Optimization started.")}

          {:error, reason} ->
            {:reply,
             optimization_request_reply(
               "rejected",
               request.graph_id,
               request.correlation_id,
               reason
             ), socket}
        end

      {:error, _changeset} ->
        {:reply,
         optimization_request_reply(
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
              run_count: experiment.completed_trials,
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
    {:noreply,
     push_failure_event(
       socket,
       "simulation_failed",
       SimulationFailedEvent,
       "Simulation failed",
       payload
     )}
  end

  def handle_info({:simulation_progress, payload}, socket) do
    {:noreply,
     push_contract_event(socket, "simulation_progress", SimulationProgressEvent, payload)}
  end

  def handle_info({:optimization_completed, payload}, socket) do
    {:noreply,
     push_contract_event(socket, "optimization_completed", OptimizationCompletedEvent, payload)}
  end

  def handle_info({:optimization_failed, payload}, socket) do
    {:noreply,
     push_failure_event(
       socket,
       "optimization_failed",
       OptimizationFailedEvent,
       "Optimization failed",
       payload
     )}
  end

  def handle_info({:optimization_progress, payload}, socket) do
    {:noreply,
     push_contract_event(socket, "optimization_progress", OptimizationProgressEvent, payload)}
  end

  def handle_info({:report_result, experiment_id, graph_id, result}, socket) do
    socket =
      if is_map(result) and result[:charts] do
        push_event(socket, "simulation_report_ready", result)
      else
        push_contract_event(socket, "simulation_report_error", SimulationReportErrorEvent, %{
          experiment_id: experiment_id,
          graph_id: graph_id,
          reason: to_string((is_map(result) && result[:status]) || "unknown_error")
        })
      end

    {:noreply, socket}
  end

  defp fetch_simulation_report(params) do
    case FetchSimulationReportPayload.validate(params) do
      {:ok, request} ->
        fetch_report(request)

      {:error, _changeset} ->
        %{status: "not_found"}
    end
  end

  defp fetch_report(request) do
    case Simulations.get_report(request.experiment_id) do
      %NetworkDefense.Simulation.SimulationReport{} = report ->
        if report_matches_graph?(report, request.graph_id) do
          simulation_report_reply(report)
        else
          %{status: "graph_version_mismatch"}
        end

      _ ->
        %{status: "not_found"}
    end
  end

  defp report_matches_graph?(report, graph_id) do
    report.graph_id == graph_id and report.graph.lock_version == report.graph_version_at_sim
  end

  defp simulation_report_reply(report) do
    case FetchSimulationReportReply.from_domain(report, report.graph) do
      {:ok, reply} -> FetchSimulationReportReply.to_wire(reply)
      {:error, _changeset} -> %{status: "not_found"}
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
         assign(socket, :graph_summaries, graph_summaries())}

      {:error, _changeset} ->
        {:reply, save_graph_reply("unmapped_error"), socket}
    end
  end

  defp save_error_status(:stale), do: "stale"
  defp save_error_status(:not_found), do: "not_found"
  defp save_error_status(:invalid_graph), do: "invalid_graph"
  defp save_error_status(_reason), do: "unmapped_error"

  defp graph_summaries do
    Graphs.list_summaries()
    |> Enum.flat_map(fn summary ->
      case GraphSummary.from_domain(summary) do
        {:ok, graph_summary} -> [GraphSummary.to_wire(graph_summary)]
        {:error, _changeset} -> []
      end
    end)
  end

  defp simulation_request_reply(status, graph_id, correlation_id, reason) do
    contract_reply(RunSimulationReply, %{
      status: status,
      graph_id: string_or_empty(graph_id),
      correlation_id: string_or_empty(correlation_id),
      reason: reason
    })
  end

  defp optimization_request_reply(status, graph_id, correlation_id, reason) do
    contract_reply(RunOptimizationReply, %{
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

  defp graph_connectivity_reply do
    contract_reply(GraphConnectivityReply, %{rules: SemanticConnectivity.rules()})
  end

  defp node_draft_reply(status, node \\ nil) do
    contract_reply(CreateNodeDraftReply, %{status: status, node: node})
  end

  defp connection_draft_reply(status, node \\ nil, edge \\ nil) do
    contract_reply(CreateConnectionDraftReply, %{status: status, node: node, edge: edge})
  end

  defp connection_target(%{target_id: target_id, target_type: target_type})
       when is_binary(target_id) and is_binary(target_type),
       do: {:ok, nil, %{id: target_id, type: target_type}}

  defp connection_target(%{new_node_type: type, x_pos: x_pos, y_pos: y_pos}) do
    with {:ok, node} <- Node.draft(type, %{x_pos: x_pos, y_pos: y_pos}) do
      {:ok, node, %{id: node.id, type: node.type}}
    end
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

  defp push_failure_event(socket, event, contract, message, payload) do
    case contract.validate(payload) do
      {:ok, event_payload} ->
        socket
        |> push_event(event, contract.to_wire(event_payload))
        |> put_flash(:error, "#{message}: #{event_payload.reason}")

      {:error, _changeset} ->
        socket
    end
  end
end
