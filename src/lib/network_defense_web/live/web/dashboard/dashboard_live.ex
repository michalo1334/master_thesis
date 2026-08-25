defmodule NetworkDefenseWeb.DashboardLive do
  use NetworkDefenseWeb, :live_view

  alias NetworkDefense.Errors
  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.EvaluationRuns
  alias NetworkDefense.Evaluation.EvaluationWorker
  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefense.Graph.{Edge, Folders, Graph, GraphDiff, Graphs, Node}
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.Graph.SemanticConnectivity
  alias NetworkDefense.Nodes.{Host, NetworkSegment}
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Relationships.SegmentReachability
  alias NetworkDefense.Runs
  alias NetworkDefense.Simulations
  alias NetworkDefense.DocumentCatalog
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
    FetchGraphProjectionPayload,
    FetchGraphProjectionReply,
    FetchDocumentCatalogPayload,
    FetchDocumentCatalogReply,
    CreateFolderPayload,
    CreateFolderReply,
    CreateNodeDraftPayload,
    CreateNodeDraftReply,
    DeleteFolderPayload,
    DeleteFolderReply,
    ExecutionProgressEvent,
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
    OptimizationReportErrorEvent,
    OptimizationReportReadyEvent,
    RunOptimizationPayload,
    RunOptimizationReply,
    RunSimulationReply,
    RunSimulationPayload,
    ReportRequestReply,
    SaveGraphPayload,
    SaveGraphReply,
    SimulationCompletedEvent,
    SimulationFailedEvent,
    SimulationReportErrorEvent,
    SimulationReportReadyEvent,
    GetManifestPayload,
    GetManifestReply,
    ListManifestsPayload,
    ListManifestsReply,
    SaveManifestPayload,
    SaveManifestReply,
    StartEvaluationPayload,
    StartEvaluationReply,
    FetchEvaluationReportPayload,
    RequestEvaluationAnalysisPayload,
    RequestEvaluationAnalysisReply,
    EvaluationCompletedEvent,
    EvaluationFailedEvent,
    EvaluationReportErrorEvent,
    EvaluationReportReadyEvent,
    EvaluationAnalysisReadyEvent,
    EvaluationAnalysisErrorEvent,
    FetchRunsPayload,
    FetchRunsReply,
    CancelRunPayload,
    CancelRunReply,
    RunCancelledEvent
  }

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full_screen>
      <.svelte
        name="DashboardHost"
        id="dashboard"
        ssr={false}
        props={
          %{
            graphSummaries: @graph_summaries,
            folders: @folders
          }
        }
      >
        <:loading>
          <div
            role="status"
            class="dashboard-loading"
            style="min-height: 100dvh; display: grid; place-items: center; color: var(--ds-color-text); background: var(--ds-color-surface);"
          >
            Loading dashboard…
          </div>
        </:loading>
      </.svelte>
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
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Evaluation.evaluation_events_topic())
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
  def handle_event("save_manifest", params, socket) do
    case SaveManifestPayload.validate(params) do
      {:ok, request} ->
        case Evaluation.save(%{
               manifest_id: request.manifest_id,
               existing_manifest_id: request.existing_manifest_id,
               title: request.title,
               content: request.content
             }) do
          {:ok, manifest} ->
            {:reply, save_manifest_reply("ok", manifest_summary(manifest, content: true), []),
             socket}

          {:error, errors} when is_list(errors) ->
            {:reply, save_manifest_reply("invalid_manifest", nil, errors), socket}

          {:error, _reason} ->
            {:reply, save_manifest_reply("invalid_manifest", nil, []), socket}
        end

      {:error, _changeset} ->
        {:reply, save_manifest_reply("invalid_request", nil, []), socket}
    end
  end

  @impl true
  def handle_event("list_manifests", params, socket) do
    case ListManifestsPayload.validate(params) do
      {:ok, _request} ->
        manifests = Enum.map(Evaluation.list(), &manifest_summary/1)
        {:reply, list_manifests_reply(manifests), socket}

      {:error, _changeset} ->
        {:reply, list_manifests_reply([]), socket}
    end
  end

  @impl true
  def handle_event("get_manifest", params, socket) do
    case GetManifestPayload.validate(params) do
      {:ok, request} ->
        manifest =
          case Evaluation.get(request.id) do
            nil -> nil
            manifest -> manifest_summary(manifest, content: true)
          end

        {:reply, get_manifest_reply(manifest), socket}

      {:error, _changeset} ->
        {:reply, get_manifest_reply(nil), socket}
    end
  end

  @impl true
  def handle_event("start_evaluation", params, socket) do
    case StartEvaluationPayload.validate(params) do
      {:ok, request} ->
        start_evaluation(request.manifest_id, socket)

      {:error, _changeset} ->
        {:reply, start_evaluation_reply("rejected", nil, []), socket}
    end
  end

  @impl true
  def handle_event("fetch_evaluation_report", params, socket) do
    case FetchEvaluationReportPayload.validate(params) do
      {:ok, request} ->
        case start_evaluation_report_fetch(request, self()) do
          {:ok, _pid} ->
            {:reply, report_request_reply("processing"), socket}

          {:error, _reason} ->
            {:reply, report_request_reply("unavailable"),
             push_contract_event(socket, "evaluation_report_error", EvaluationReportErrorEvent, %{
               document_id: request.document_id,
               run_id: request.run_id,
               error: dashboard_error(:task_unavailable)
             })}
        end

      {:error, _changeset} ->
        {:reply, report_request_reply("invalid_params"), socket}
    end
  end

  @impl true
  def handle_event("request_evaluation_analysis", params, socket) do
    case RequestEvaluationAnalysisPayload.validate(params) do
      {:ok, request} ->
        case start_evaluation_analysis(request, self()) do
          {:ok, _pid} ->
            {:reply, analysis_request_reply("processing"), socket}

          {:error, _reason} ->
            {:reply, analysis_request_reply("unavailable"),
             push_contract_event(
               socket,
               "evaluation_analysis_error",
               EvaluationAnalysisErrorEvent,
               %{
                 document_id: request.document_id,
                 run_id: request.run_id,
                 mode: request.mode,
                 error: dashboard_error(:task_unavailable)
               }
             )}
        end

      {:error, _changeset} ->
        {:reply, analysis_request_reply("invalid_params"), socket}
    end
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
            {:reply, delete_folder_reply(status_error(reason, DeleteFolderReply)), socket}
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
            {:reply, move_graph_to_folder_reply(status_error(reason, MoveGraphToFolderReply)),
             socket}
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
  def handle_event("fetch_graph_projection", params, socket) do
    {:reply, graph_projection(params), socket}
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
    handle_run_request(
      params,
      RunSimulationPayload,
      &Simulations.run_async/1,
      &simulation_request_reply/5,
      "Simulation started.",
      socket
    )
  end

  @impl true
  def handle_event("run_optimization_request", params, socket) do
    handle_run_request(
      params,
      RunOptimizationPayload,
      &Optimizations.run_async/1,
      &optimization_request_reply/5,
      "Optimization started.",
      socket
    )
  end

  @impl true
  def handle_event("fetch_simulation_report", params, socket) do
    case FetchSimulationReportPayload.validate(params) do
      {:ok, request} ->
        case start_report_fetch(request, self()) do
          {:ok, _pid} ->
            {:reply, report_request_reply("processing"), socket}

          {:error, _reason} ->
            {:reply, report_request_reply("unavailable"),
             push_contract_event(socket, "simulation_report_error", SimulationReportErrorEvent, %{
               document_id: request.document_id,
               experiment_id: request.experiment_id,
               error: dashboard_error(:task_unavailable)
             })}
        end

      {:error, _changeset} ->
        {:reply, report_request_reply("invalid_params"), socket}
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
        case start_optimization_report_fetch(request, self()) do
          {:ok, _pid} ->
            {:reply, report_request_reply("processing"), socket}

          {:error, _reason} ->
            {:reply, report_request_reply("unavailable"),
             push_contract_event(
               socket,
               "optimization_report_error",
               OptimizationReportErrorEvent,
               %{
                 document_id: request.document_id,
                 optimization_id: request.optimization_id,
                 error: dashboard_error(:task_unavailable)
               }
             )}
        end

      {:error, _changeset} ->
        {:reply, report_request_reply("invalid_params"), socket}
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
  def handle_event("fetch_runs", params, socket) do
    case FetchRunsPayload.validate(params) do
      {:ok, _request} ->
        runs =
          Runs.active()
          |> Enum.map(&run_summary/1)

        {:ok, reply} = FetchRunsReply.validate(%{runs: runs})
        {:reply, FetchRunsReply.to_wire(reply), socket}

      {:error, _changeset} ->
        {:reply, FetchRunsReply.to_wire(%FetchRunsReply{runs: []}), socket}
    end
  end

  def handle_event("cancel_run", params, socket) do
    case CancelRunPayload.validate(params) do
      {:ok, request} ->
        case Runs.cancel(request.kind, request.run_id) do
          {:ok, _run} ->
            {:reply, contract_reply(CancelRunReply, %{status: "cancelled"}),
             push_contract_event(socket, "run_cancelled", RunCancelledEvent, %{
               kind: request.kind,
               run_id: request.run_id
             })}

          {:error, reason} when reason in [:not_found, :not_running] ->
            {:reply, contract_reply(CancelRunReply, %{status: Atom.to_string(reason)}), socket}
        end

      {:error, _changeset} ->
        {:reply, contract_reply(CancelRunReply, %{status: "invalid_params"}), socket}
    end
  end

  @impl true
  def handle_event("fetch_document_catalog", params, socket) do
    # Catalog queries reply inline. Do not defer this reply through a task or event.
    case FetchDocumentCatalogPayload.validate(params) do
      {:ok, request} ->
        {:reply, fetch_document_catalog_reply(request), socket}

      {:error, _changeset} ->
        {:reply,
         document_catalog_reply(%{
           items: [],
           related_items: [],
           total_count: 0,
           filter_options: %{}
         }), socket}
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
       failure_payload(payload)
     )}
  end

  def handle_info({:simulation_progress, payload}, socket) do
    {:noreply,
     push_contract_event(socket, "simulation_progress", ExecutionProgressEvent, payload)}
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
       failure_payload(payload)
     )}
  end

  def handle_info({:optimization_progress, payload}, socket) do
    {:noreply,
     push_contract_event(socket, "optimization_progress", ExecutionProgressEvent, payload)}
  end

  def handle_info({:evaluation_completed, payload}, socket) do
    {:noreply,
     push_contract_event(socket, "evaluation_completed", EvaluationCompletedEvent, payload)}
  end

  def handle_info({:evaluation_failed, payload}, socket) do
    {:noreply,
     push_failure_event(
       socket,
       "evaluation_failed",
       EvaluationFailedEvent,
       "Evaluation failed",
       failure_payload(payload)
     )}
  end

  def handle_info({:evaluation_progress, payload}, socket) do
    {:noreply,
     push_contract_event(socket, "evaluation_progress", ExecutionProgressEvent, payload)}
  end

  def handle_info({:simulation_report_progress, cid, gid, grev, c, t, d}, socket),
    do: push_report_progress(socket, "simulation_report_progress", cid, gid, grev, c, t, d)

  def handle_info({:optimization_report_progress, cid, gid, grev, c, t, d}, socket),
    do: push_report_progress(socket, "optimization_report_progress", cid, gid, grev, c, t, d)

  def handle_info({:evaluation_report_progress, cid, gid, grev, c, t, d}, socket),
    do: push_report_progress(socket, "evaluation_report_progress", cid, gid, grev, c, t, d)

  def handle_info({:evaluation_report_result, document_id, run_id, result}, socket) do
    {:noreply,
     push_report_result(
       socket,
       result,
       document_id,
       run_id,
       {EvaluationReportReadyEvent, "evaluation_report_ready"},
       {EvaluationReportErrorEvent, "evaluation_report_error"},
       :run_id
     )}
  end

  def handle_info({:evaluation_analysis_result, document_id, run_id, mode, result}, socket) do
    case result do
      {:ok, analysis} ->
        {:noreply,
         push_contract_event(socket, "evaluation_analysis_ready", EvaluationAnalysisReadyEvent, %{
           document_id: document_id,
           run_id: run_id,
           mode: mode,
           analysis: analysis
         })}

      {:error, reason} ->
        {:noreply,
         push_contract_event(socket, "evaluation_analysis_error", EvaluationAnalysisErrorEvent, %{
           document_id: document_id,
           run_id: run_id,
           mode: mode,
           error: dashboard_error(reason)
         })}
    end
  end

  def handle_info({:report_result, document_id, experiment_id, result}, socket) do
    {:noreply,
     push_report_result(
       socket,
       result,
       document_id,
       experiment_id,
       {SimulationReportReadyEvent, "simulation_report_ready"},
       {SimulationReportErrorEvent, "simulation_report_error"},
       :experiment_id
     )}
  end

  def handle_info(
        {:optimization_report_result, document_id, optimization_id, result},
        socket
      ) do
    {:noreply,
     push_report_result(
       socket,
       result,
       document_id,
       optimization_id,
       {OptimizationReportReadyEvent, "optimization_report_ready"},
       {OptimizationReportErrorEvent, "optimization_report_error"},
       :optimization_id
     )}
  end

  defp push_report_result(
         socket,
         result,
         document_id,
         correlation_id,
         {ready_contract, ready_event},
         {error_contract, error_event},
         id_field
       ) do
    case result do
      {:ok, report} ->
        push_contract_event(socket, ready_event, ready_contract, %{
          document_id: document_id,
          report: report
        })

      {:error, {reason, _detail}} ->
        error_payload =
          %{document_id: document_id, error: dashboard_error(reason)}
          |> Map.put(id_field, correlation_id)

        push_contract_event(socket, error_event, error_contract, error_payload)
    end
  end

  defp fetch_report(request, on_progress) do
    case Simulations.get_report(request.experiment_id, on_progress) do
      %NetworkDefense.Simulation.SimulationReport{} = report ->
        simulation_report_reply(report)

      _ ->
        {:error, {:not_found, nil}}
    end
  end

  defp simulation_report_reply(report) do
    case FetchSimulationReportReply.from_domain(report) do
      {:ok, reply} -> {:ok, FetchSimulationReportReply.to_wire(reply)}
      {:error, _changeset} -> {:error, {:not_found, nil}}
    end
  end

  defp fetch_optimization_report(%FetchOptimizationReportPayload{} = request, on_progress) do
    case Optimizations.get_report(request.optimization_id, on_progress) do
      %NetworkDefense.Optimization.OptimizationReport{} = report ->
        optimization_report_reply(report)

      _ ->
        {:error, {:not_found, nil}}
    end
  end

  defp optimization_report_reply(report) do
    case FetchOptimizationReportReply.from_domain(report) do
      {:ok, reply} -> {:ok, FetchOptimizationReportReply.to_wire(reply)}
      {:error, _changeset} -> {:error, {:not_found, nil}}
    end
  end

  defp start_report_fetch(%FetchSimulationReportPayload{} = request, owner) do
    start_report_task(
      owner,
      :simulation_report_progress,
      request.experiment_id,
      :report_result,
      request.document_id,
      &fetch_report(request, &1)
    )
  end

  defp start_optimization_report_fetch(%FetchOptimizationReportPayload{} = request, owner) do
    start_report_task(
      owner,
      :optimization_report_progress,
      request.optimization_id,
      :optimization_report_result,
      request.document_id,
      &fetch_optimization_report(request, &1)
    )
  end

  defp start_evaluation_report_fetch(%FetchEvaluationReportPayload{} = request, owner) do
    start_report_task(
      owner,
      :evaluation_report_progress,
      request.run_id,
      :evaluation_report_result,
      request.document_id,
      fn on_progress ->
        case Evaluation.report(request.run_id, on_progress) do
          nil -> {:error, {:not_found, nil}}
          report -> {:ok, report}
        end
      end
    )
  end

  defp start_evaluation_analysis(%RequestEvaluationAnalysisPayload{} = request, owner) do
    TaskSupervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
      result =
        case Evaluation.analyze(request.run_id, request.mode) do
          {:ok, zip} ->
            Evaluation.parse_analysis(zip)

          error ->
            error
        end

      send(
        owner,
        {:evaluation_analysis_result, request.document_id, request.run_id, request.mode, result}
      )
    end)
  end

  defp start_report_task(owner, progress_tag, correlation_id, result_tag, document_id, fetch_fun) do
    TaskSupervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
      result =
        try do
          fetch_fun.(report_progress_sender(owner, progress_tag, correlation_id))
        rescue
          # Expected infra failures become error events; anything else is a bug
          # and crashes the task (logged by the task supervisor).
          error in [DBConnection.ConnectionError, Postgrex.Error] ->
            {:error, {:internal_error, Exception.message(error)}}
        end

      send(owner, {result_tag, document_id, correlation_id, result})
    end)
  end

  defp run_summary(run) do
    %{
      id: run.id,
      kind: run.kind,
      title: run.title,
      status: run.status,
      completed: run.completed,
      total: run.total,
      started_at: run.started_at && DateTime.to_iso8601(run.started_at)
    }
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

  defp document_catalog_reply(attrs) do
    {:ok, reply} = FetchDocumentCatalogReply.validate(attrs)
    FetchDocumentCatalogReply.to_wire(reply)
  end

  defp fetch_document_catalog_reply(request) do
    request
    |> DocumentCatalog.document_catalog()
    |> document_catalog_reply()
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

  defp simulation_request_reply(status, graph_revision_id, correlation_id, error) do
    simulation_request_reply(status, graph_revision_id, correlation_id, error, nil)
  end

  defp simulation_request_reply(status, graph_revision_id, correlation_id, error, run_id) do
    run_request_reply(
      RunSimulationReply,
      status,
      graph_revision_id,
      correlation_id,
      error,
      run_id
    )
  end

  defp optimization_request_reply(status, graph_revision_id, correlation_id, error) do
    optimization_request_reply(status, graph_revision_id, correlation_id, error, nil)
  end

  defp optimization_request_reply(status, graph_revision_id, correlation_id, error, run_id) do
    run_request_reply(
      RunOptimizationReply,
      status,
      graph_revision_id,
      correlation_id,
      error,
      run_id
    )
  end

  defp run_request_reply(contract, status, graph_revision_id, correlation_id, error, run_id) do
    contract_reply(contract, %{
      status: status,
      graph_revision_id: string_or_empty(graph_revision_id),
      correlation_id: string_or_empty(correlation_id),
      run_id: string_or_empty(run_id),
      error: dashboard_error(error)
    })
  end

  defp handle_run_request(params, payload_mod, run_fun, reply_fun, success_flash, socket) do
    case payload_mod.validate(params) do
      {:ok, %{request: request}} ->
        case run_fun.(request) do
          {:ok, job} ->
            {:reply,
             reply_fun.(
               "accepted",
               request.graph_revision_id,
               request.correlation_id,
               nil,
               get_in(job.args, ["experiment_id"]) || get_in(job.args, ["run_id"])
             ), put_flash(socket, :info, success_flash)}

          {:error, reason} ->
            {:reply,
             reply_fun.(
               "rejected",
               request.graph_revision_id,
               request.correlation_id,
               reason,
               nil
             ), socket}
        end

      {:error, _changeset} ->
        {:reply,
         reply_fun.(
           "rejected",
           params |> Map.get("request", %{}) |> Map.get("graph_revision_id"),
           params |> Map.get("request", %{}) |> Map.get("correlation_id"),
           :invalid_request,
           nil
         ), socket}
    end
  end

  defp string_or_empty(value) when is_binary(value), do: value
  defp string_or_empty(_value), do: ""

  defp report_request_reply(status), do: contract_reply(ReportRequestReply, %{status: status})

  defp analysis_request_reply(status),
    do: contract_reply(RequestEvaluationAnalysisReply, %{status: status})

  defp failure_payload(payload) do
    payload
    |> Map.delete(:reason)
    |> Map.put(:error, dashboard_error(Map.get(payload, :reason)))
  end

  defp dashboard_error(nil), do: nil
  defp dashboard_error(error), do: %{code: Errors.to_wire(error)}

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

  defp save_manifest_reply(status, manifest, errors) do
    contract_reply(SaveManifestReply, %{status: status, manifest: manifest, errors: errors})
  end

  defp list_manifests_reply(manifests),
    do: contract_reply(ListManifestsReply, %{manifests: manifests})

  defp get_manifest_reply(manifest),
    do: contract_reply(GetManifestReply, %{manifest: manifest})

  defp start_evaluation_reply(status, run_id, errors) do
    contract_reply(StartEvaluationReply, %{status: status, run_id: run_id, errors: errors})
  end

  defp manifest_summary(manifest, opts \\ []) do
    summary = %{
      id: manifest.id,
      manifest_id: manifest.manifest_id,
      title: manifest.title
    }

    if Keyword.get(opts, :content, false) do
      Map.put(summary, :content, manifest.content)
    else
      summary
    end
  end

  defp start_evaluation_task(run_id) do
    OpentelemetryOban.insert(EvaluationWorker.new(%{"run_id" => run_id}))
  end

  defp start_evaluation(manifest_id, socket) do
    case Evaluation.start(manifest_id) do
      {:ok, run} ->
        case start_evaluation_task(run.id) do
          {:ok, _job} ->
            {:reply, start_evaluation_reply("accepted", run.id, []),
             put_flash(socket, :info, "Evaluation started.")}

          {:error, _reason} ->
            EvaluationRuns.fail(run, "task_unavailable")
            {:reply, start_evaluation_reply("rejected", nil, []), socket}
        end

      {:error, :not_found} ->
        {:reply, start_evaluation_reply("not_found", nil, []), socket}

      {:error, errors} when is_list(errors) ->
        {:reply, start_evaluation_reply("rejected", nil, errors), socket}

      {:error, _reason} ->
        {:reply, start_evaluation_reply("rejected", nil, []), socket}
    end
  end

  defp create_folder_reply(status, folder \\ nil) do
    contract_reply(CreateFolderReply, %{status: status, folder: folder})
  end

  defp delete_folder_reply(status), do: contract_reply(DeleteFolderReply, %{status: status})

  defp move_graph_to_folder_reply(status),
    do: contract_reply(MoveGraphToFolderReply, %{status: status})

  defp status_error(reason, reply_contract) do
    %{enum_values: %{status: statuses}} = reply_contract.contract_meta()
    if reason in statuses, do: Atom.to_string(reason), else: "unmapped_error"
  end

  defp graph_connectivity_reply do
    contract_reply(GraphConnectivityReply, %{rules: SemanticConnectivity.rules()})
  end

  defp graph_projection(params) do
    case FetchGraphProjectionPayload.validate(params) do
      {:ok, request} ->
        case Graphs.load_revision(request.graph_revision_id) do
          %Graph{} = graph -> graph_projection_reply(build_graph_projection(graph))
          nil -> graph_projection_reply("not_found")
          {:error, _reason} -> graph_projection_reply("unmapped_error")
        end

      {:error, _changeset} ->
        graph_projection_reply("invalid_graph")
    end
  end

  defp build_graph_projection(%Graph{} = graph) do
    graph = MaterializeReachability.materialize(graph)

    %{
      status: "ok",
      segments: projection_ids(Graph.nodes(graph), NetworkSegment),
      hosts: projection_ids(Graph.nodes(graph), Host),
      policy_links: projection_links(Graph.edges(graph), SegmentReachability),
      operational_flows: MaterializeReachability.operational_flows(graph)
    }
  end

  defp projection_ids(nodes, type) do
    Enum.map(Enum.filter(nodes, &(&1.type == type)), fn node -> %{id: node.id} end)
  end

  defp projection_links(edges, type) do
    Enum.map(Enum.filter(edges, &(&1.type == type)), fn edge ->
      %{id: edge.id, from_id: edge.from_id, to_id: edge.to_id}
    end)
  end

  defp graph_projection_reply(status) when is_binary(status) do
    contract_reply(FetchGraphProjectionReply, %{status: status})
  end

  defp graph_projection_reply(attrs) do
    contract_reply(FetchGraphProjectionReply, attrs)
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

  defp push_report_progress(
         socket,
         event,
         correlation_id,
         graph_id,
         graph_revision_id,
         completed,
         total,
         detail
       ) do
    {:noreply,
     push_contract_event(socket, event, ExecutionProgressEvent, %{
       correlation_id: correlation_id,
       graph_id: graph_id,
       graph_revision_id: graph_revision_id,
       completed: completed,
       total: total,
       detail: detail
     })}
  end

  defp report_progress_sender(owner, tag, correlation_id) do
    fn graph_id, graph_revision_id, completed, total, detail ->
      send(owner, {tag, correlation_id, graph_id, graph_revision_id, completed, total, detail})
    end
  end

  defp push_failure_event(socket, event, contract, message, payload) do
    case contract.validate(payload) do
      {:ok, event_payload} ->
        socket
        |> push_event(event, contract.to_wire(event_payload))
        |> put_flash(:error, message)

      {:error, _changeset} ->
        socket
    end
  end
end
