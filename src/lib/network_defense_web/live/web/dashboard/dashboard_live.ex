defmodule NetworkDefenseWeb.DashboardLive do
  use NetworkDefenseWeb, :live_view

  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefense.Graph.{Edge, Folders, GraphDiff, Graphs, Node}
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
    CompareGraphsPayload,
    CompareGraphsReply,
    CreateFolderPayload,
    CreateFolderReply,
    CreateNodeDraftPayload,
    CreateNodeDraftReply,
    DeleteFolderPayload,
    DeleteFolderReply,
    FolderSummary,
    GraphConnectivityReply,
    OpenGraphPayload,
    OpenGraphReply,
    SetGraphRevisionFavoritePayload,
    SetGraphRevisionFavoriteReply,
    GraphSummary,
    MoveGraphToFolderPayload,
    MoveGraphToFolderReply,
    FetchOptimizationReportPayload,
    FetchOptimizationReportReply,
    FetchOptimizationRunsPayload,
    FetchOptimizationRunsReply,
    OptimizationCompletedEvent,
    OptimizationFailedEvent,
    OptimizationProgressEvent,
    OptimizationReportErrorEvent,
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
            graphSummaries: @graph_summaries,
            folders: @folders
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
      |> assign(:folders, folder_summaries())

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
  def handle_event("compare_graphs", params, socket) do
    {:reply, compare_graphs(params), socket}
  end

  @impl true
  def handle_event("set_graph_revision_favorite", params, socket) do
    {:reply, set_graph_revision_favorite(params), socket}
  end

  @impl true
  def handle_event("create_folder", params, socket) do
    case CreateFolderPayload.validate(params) do
      {:ok, request} ->
        create_folder(request.name, socket)

      {:error, _changeset} ->
        {:reply, create_folder_reply("invalid_folder"), socket}
    end
  end

  @impl true
  def handle_event("delete_folder", params, socket) do
    case DeleteFolderPayload.validate(params) do
      {:ok, request} ->
        case Folders.delete(request.folder_id) do
          {:ok, _folder} ->
            {:reply, delete_folder_reply("ok"), refresh_folder_assigns(socket)}

          {:error, reason} ->
            {:reply, delete_folder_reply(folder_delete_error_status(reason)), socket}
        end

      {:error, _changeset} ->
        {:reply, delete_folder_reply("invalid_folder"), socket}
    end
  end

  @impl true
  def handle_event("move_graph_to_folder", params, socket) do
    case MoveGraphToFolderPayload.validate(params) do
      {:ok, request} ->
        case Folders.move_graph(request.graph_id, request.folder_id) do
          {:ok, _graph} ->
            {:reply, move_graph_to_folder_reply("ok"),
             assign(socket, :graph_summaries, graph_summaries())}

          {:error, reason} ->
            {:reply, move_graph_to_folder_reply(move_graph_error_status(reason)), socket}
        end

      {:error, _changeset} ->
        {:reply, move_graph_to_folder_reply("invalid_graph"), socket}
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
             simulation_request_reply(
               "accepted",
               request.graph_revision_id,
               request.correlation_id,
               nil
             ), put_flash(socket, :info, "Simulation started.")}

          {:error, reason} ->
            {:reply,
             simulation_request_reply(
               "rejected",
               request.graph_revision_id,
               request.correlation_id,
               reason
             ), socket}
        end

      {:error, _changeset} ->
        {:reply,
         simulation_request_reply(
           "rejected",
           params |> Map.get("request", %{}) |> Map.get("graph_revision_id"),
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
               request.graph_revision_id,
               request.correlation_id,
               nil
             ), put_flash(socket, :info, "Optimization started.")}

          {:error, reason} ->
            {:reply,
             optimization_request_reply(
               "rejected",
               request.graph_revision_id,
               request.correlation_id,
               reason
             ), socket}
        end

      {:error, _changeset} ->
        {:reply,
         optimization_request_reply(
           "rejected",
           params |> Map.get("request", %{}) |> Map.get("graph_revision_id"),
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
          request.graph_revision_ids
          |> Simulations.list_experiments()
          |> Enum.map(fn experiment ->
            %{
              id: experiment.id,
              graph_id: experiment.graph_revision.graph_id,
              graph_revision_id: experiment.graph_revision_id,
              graph_title: experiment.graph_revision.title,
              seed: experiment.master_seed,
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
  def handle_event("fetch_optimization_report", params, socket) do
    case FetchOptimizationReportPayload.validate(params) do
      {:ok, request} ->
        case start_optimization_report_fetch(request, params, self()) do
          {:ok, _pid} -> {:reply, %{status: "processing"}, socket}
          {:error, _reason} -> {:reply, %{status: "unavailable"}, socket}
        end

      {:error, _changeset} ->
        {:reply, %{status: "invalid_params"}, socket}
    end
  end

  def handle_event("fetch_optimization_runs", params, socket) do
    case FetchOptimizationRunsPayload.validate(params) do
      {:ok, request} ->
        runs =
          Optimizations.list_runs(request.graph_revision_ids)
          |> Enum.map(&optimization_run_summary/1)

        {:ok, reply} = FetchOptimizationRunsReply.validate(%{runs: runs})
        {:reply, FetchOptimizationRunsReply.to_wire(reply), socket}

      {:error, _changeset} ->
        {:reply, FetchOptimizationRunsReply.to_wire(%FetchOptimizationRunsReply{runs: []}),
         socket}
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

  def handle_info({:report_result, experiment_id, graph_revision_id, result}, socket) do
    socket =
      if is_map(result) and result[:charts] do
        push_event(socket, "simulation_report_ready", result)
      else
        push_contract_event(socket, "simulation_report_error", SimulationReportErrorEvent, %{
          experiment_id: experiment_id,
          graph_revision_id: graph_revision_id,
          reason: to_string((is_map(result) && result[:status]) || "unknown_error")
        })
      end

    {:noreply, socket}
  end

  def handle_info(
        {:optimization_report_result, optimization_id, graph_revision_id, result},
        socket
      ) do
    socket =
      if is_map(result) and result[:report] do
        push_event(socket, "optimization_report_ready", result)
      else
        push_contract_event(socket, "optimization_report_error", OptimizationReportErrorEvent, %{
          optimization_id: optimization_id,
          graph_revision_id: graph_revision_id,
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
        if report.graph_revision_id == request.graph_revision_id do
          simulation_report_reply(report)
        else
          %{status: "not_found"}
        end

      _ ->
        %{status: "not_found"}
    end
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
        {:report_result, request.experiment_id, request.graph_revision_id, report_result(params)}
      )
    end)
  end

  defp report_result(params) do
    fetch_simulation_report(params)
  end

  defp start_optimization_report_fetch(request, params, owner) do
    TaskSupervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
      send(
        owner,
        {:optimization_report_result, request.optimization_id, request.graph_revision_id,
         optimization_report_result(params)}
      )
    end)
  end

  defp optimization_report_result(params) do
    fetch_optimization_report_params(params)
  end

  defp fetch_optimization_report_params(params) do
    case FetchOptimizationReportPayload.validate(params) do
      {:ok, request} -> fetch_optimization_report(request)
      {:error, _changeset} -> %{status: "not_found"}
    end
  end

  defp fetch_optimization_report(%FetchOptimizationReportPayload{} = request) do
    case Optimizations.get_report(request.optimization_id) do
      %{graph_revision_id: graph_revision_id} = report
      when graph_revision_id == request.graph_revision_id ->
        optimization_report_reply(report)

      _ ->
        %{status: "not_found"}
    end
  end

  defp optimization_report_reply(report) do
    case FetchOptimizationReportReply.from_domain(report) do
      {:ok, reply} -> FetchOptimizationReportReply.to_wire(reply)
      {:error, _changeset} -> %{status: "not_found"}
    end
  end

  defp optimization_run_summary(run) do
    %{
      id: run.id,
      graph_id: run.graph_revision.graph_id,
      graph_revision_id: run.graph_revision_id,
      graph_title: run.graph_revision.title,
      strategy: run.strategy,
      requested_budget: run.requested_budget,
      used_budget: run.used_budget,
      runtime_ms: run.runtime_ms,
      output_graph_revision_id: run.output_graph_revision_id,
      started_at: run.inserted_at && DateTime.to_iso8601(run.inserted_at)
    }
  end

  defp open_graph(params) do
    case OpenGraphPayload.validate(params) do
      {:ok, request} -> graph_open_reply(Graphs.load_revision(request.graph_revision_id))
      {:error, _changeset} -> open_graph_reply("invalid_graph")
    end
  end

  defp graph_open_reply(nil), do: open_graph_reply("not_found")
  defp graph_open_reply({:error, _reason}), do: open_graph_reply("unmapped_error")

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

  defp compare_graphs(params) do
    case CompareGraphsPayload.validate(params) do
      {:ok, request} -> compare_validated_graphs(request)
      {:error, _changeset} -> compare_graphs_reply("invalid_graph")
    end
  end

  defp set_graph_revision_favorite(params) do
    case SetGraphRevisionFavoritePayload.validate(params) do
      {:ok, request} ->
        case Graphs.set_favorite(request.graph_revision_id, request.favorite) do
          {:ok, favorite} -> graph_revision_favorite_reply("ok", favorite)
          {:error, :not_found} -> graph_revision_favorite_reply("not_found", false)
          {:error, :invalid_graph} -> graph_revision_favorite_reply("invalid_graph", false)
          {:error, _reason} -> graph_revision_favorite_reply("unmapped_error", false)
        end

      {:error, _changeset} ->
        graph_revision_favorite_reply("invalid_graph", false)
    end
  end

  defp create_folder(name, socket) do
    case Folders.create(name) do
      {:ok, folder} ->
        case FolderSummary.from_domain(folder) do
          {:ok, summary} ->
            {:reply, create_folder_reply("ok", FolderSummary.to_wire(summary)),
             assign(socket, :folders, folder_summaries())}

          {:error, _changeset} ->
            {:reply, create_folder_reply("unmapped_error"), socket}
        end

      {:error, _reason} ->
        {:reply, create_folder_reply("invalid_folder"), socket}
    end
  end

  defp compare_validated_graphs(request) do
    with %NetworkDefense.Graph.Graph{} = base <- Graphs.load_revision(request.base_revision_id),
         %NetworkDefense.Graph.Graph{} = comparison <-
           Graphs.load_revision(request.comparison_revision_id),
         %{graph: graph} = diff <- GraphDiff.structural(base, comparison),
         {:ok, wire_graph} <- GraphContract.from_domain(graph) do
      compare_graphs_reply("ok", Map.put(diff, :graph, wire_graph))
    else
      nil -> compare_graphs_reply("not_found")
      _error -> compare_graphs_reply("unmapped_error")
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

  defp folder_summaries do
    Folders.list()
    |> Enum.flat_map(fn folder ->
      case FolderSummary.from_domain(folder) do
        {:ok, summary} -> [FolderSummary.to_wire(summary)]
        {:error, _changeset} -> []
      end
    end)
  end

  defp refresh_folder_assigns(socket) do
    socket
    |> assign(:folders, folder_summaries())
    |> assign(:graph_summaries, graph_summaries())
  end

  defp simulation_request_reply(status, graph_revision_id, correlation_id, reason) do
    contract_reply(RunSimulationReply, %{
      status: status,
      graph_revision_id: string_or_empty(graph_revision_id),
      correlation_id: string_or_empty(correlation_id),
      reason: reason
    })
  end

  defp optimization_request_reply(status, graph_revision_id, correlation_id, reason) do
    contract_reply(RunOptimizationReply, %{
      status: status,
      graph_revision_id: string_or_empty(graph_revision_id),
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

  defp compare_graphs_reply(status, result \\ nil) do
    contract_reply(CompareGraphsReply, %{status: status, result: result})
  end

  defp graph_revision_favorite_reply(status, favorite) do
    contract_reply(SetGraphRevisionFavoriteReply, %{status: status, favorite: favorite})
  end

  defp create_folder_reply(status, folder \\ nil) do
    contract_reply(CreateFolderReply, %{status: status, folder: folder})
  end

  defp delete_folder_reply(status), do: contract_reply(DeleteFolderReply, %{status: status})

  defp move_graph_to_folder_reply(status),
    do: contract_reply(MoveGraphToFolderReply, %{status: status})

  defp folder_delete_error_status(:not_found), do: "not_found"
  defp folder_delete_error_status(:invalid_folder), do: "invalid_folder"
  defp folder_delete_error_status(_reason), do: "unmapped_error"

  defp move_graph_error_status(:not_found), do: "not_found"
  defp move_graph_error_status(:invalid_graph), do: "invalid_graph"
  defp move_graph_error_status(:invalid_folder), do: "invalid_folder"
  defp move_graph_error_status(:folder_not_found), do: "folder_not_found"
  defp move_graph_error_status(_reason), do: "unmapped_error"

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
