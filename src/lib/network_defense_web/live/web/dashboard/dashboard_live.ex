defmodule NetworkDefenseWeb.DashboardLive do
  use NetworkDefenseWeb, :live_view

  require Logger

  alias NetworkDefense.Errors
  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.EvaluationRuns
  alias NetworkDefense.Evaluation.EvaluationWorker
  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefense.Graph.{Edge, Folders, Graph, GraphDiff, Graphs, Node, TopologyProjection}
  alias NetworkDefense.Graph.SemanticConnectivity
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Runs
  alias NetworkDefense.Simulations
  alias NetworkDefense.DocumentCatalog
  alias OpentelemetryProcessPropagator.Task.Supervisor, as: TaskSupervisor

  alias NetworkDefenseWeb.Contracts.Dashboard.ExecutionProgressEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.ReportRequestReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysisErrorEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysisReadyEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationCompletedEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationFailedEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationReportErrorEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationReportReadyEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.DescribeManifestPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.DescribeManifestReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.FetchEvaluationReportPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.GetManifestPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.GetManifestReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ListManifestsPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ListManifestsReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.RequestEvaluationAnalysisPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.RequestEvaluationAnalysisReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.SaveManifestPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.SaveManifestReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StartEvaluationPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StartEvaluationReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.CompareGraphsPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.CompareGraphsReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.CreateConnectionDraftPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.CreateConnectionDraftReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.CreateFolderPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.CreateFolderReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.CreateNodeDraftPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.CreateNodeDraftReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.DeleteFolderPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.DeleteFolderReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.FolderSummary
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphConnectivityReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphSummary
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.MoveGraphToFolderPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.MoveGraphToFolderReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.OpenGraphPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.OpenGraphReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.ProjectTopologyDraftPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.ProjectTopologyDraftReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.SaveGraphPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.SaveGraphReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.SetGraphRevisionFavoritePayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.SetGraphRevisionFavoriteReply

  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection,
    as: TopologyProjectionContract

  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.FetchOptimizationReportPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.FetchOptimizationReportReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.FetchOptimizationRunsPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.FetchOptimizationRunsReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.OptimizationCompletedEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.OptimizationFailedEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.OptimizationReportErrorEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.OptimizationReportReadyEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.RunOptimizationPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.RunOptimizationReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Runs.CancelRunPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Runs.CancelRunReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Runs.FetchRunsPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Runs.FetchRunsReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Runs.RunCancelledEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.FetchExperimentsPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.FetchExperimentsReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.FetchSimulationReportPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.FetchSimulationReportReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.RunSimulationPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.RunSimulationReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationCompletedEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationFailedEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportErrorEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportReadyEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Workspace.FetchDocumentCatalogPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Workspace.FetchDocumentCatalogReply

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
            style="min-height: 100dvh; display: grid; place-items: center; color: var(--ui-color-text); background: var(--ui-color-surface);"
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

      {:error, changeset} ->
        {:reply, save_graph_reply("invalid_graph", nil, graph_validation_errors(changeset)),
         socket}
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
  def handle_event("describe_manifest", params, socket) do
    case DescribeManifestPayload.validate(params) do
      {:ok, request} ->
        case Evaluation.describe_manifest(request.content) do
          {:ok, description} ->
            {:reply,
             describe_manifest_reply(
               "ok",
               description["plans"],
               description["comparison_groups"],
               []
             ), socket}

          {:error, errors} ->
            {:reply, describe_manifest_reply("invalid_manifest", [], [], errors), socket}
        end

      {:error, _changeset} ->
        {:reply, describe_manifest_reply("invalid_request", [], [], []), socket}
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
  def handle_event("project_topology_draft", params, socket) do
    {:reply, project_topology_draft(params), socket}
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

  # Public only so the two failure classes stay testable: a missing report is a
  # `not_found` lookup, while a report that loads but fails wire mapping is a
  # server defect and must never surface as `not_found`.
  @doc false
  def simulation_report_reply(report) do
    with {:ok, projection} <- simulation_report_projection(report),
         {:ok, reply} <- simulation_report_contract(report, projection) do
      {:ok, FetchSimulationReportReply.to_wire(reply)}
    else
      {:error, stage, reason} ->
        log_report_wire_failure(stage, report, reason)
        {:error, {:internal_error, stage}}
    end
  end

  defp simulation_report_projection(report) do
    case topology_projection(report.graph) do
      {:ok, projection} -> {:ok, projection}
      {:error, reason} -> {:error, "topology_projection", reason}
    end
  end

  defp simulation_report_contract(report, projection) do
    case FetchSimulationReportReply.from_domain(report, projection) do
      {:ok, reply} -> {:ok, reply}
      {:error, reason} -> {:error, "report_contract", reason}
    end
  end

  defp log_report_wire_failure(stage, report, reason) do
    Logger.error("simulation report loaded but wire mapping failed",
      stage: stage,
      graph_id: report.graph_id,
      graph_revision_id: report.graph_revision_id,
      reason: wire_failure_fields(reason)
    )
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
    with {:ok, wire_graph} <- GraphContract.from_domain(graph),
         {:ok, wire_projection} <- topology_projection(graph) do
      open_graph_reply("ok", wire_graph, wire_projection)
    else
      _error -> open_graph_reply("unmapped_error")
    end
  end

  defp save_graph(graph, socket) do
    case Graphs.replace(graph) do
      {:ok, %{graph: persisted}} ->
        save_graph_success(persisted, socket)

      {:error, reason} ->
        {:reply,
         save_graph_reply(save_error_status(reason), nil, [
           validation_error("graph", nil, [], Errors.to_wire(reason))
         ]), socket}
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
    case save_graph_wire(persisted) do
      {:ok, wire_graph, wire_projection} ->
        {:reply, save_graph_reply("ok", wire_graph, [], wire_projection),
         assign(socket, :graph_summaries, graph_summaries())}

      {:error, stage, reason} ->
        log_post_persist_wire_failure(stage, persisted, reason)
        {:reply, save_graph_reply("unmapped_error"), socket}
    end
  end

  # The graph is persisted at this point. A failure here returns an error reply
  # for a save that did happen, so log it without graph data and without retry.
  defp save_graph_wire(persisted) do
    case GraphContract.from_domain(persisted) do
      {:ok, wire_graph} ->
        case topology_projection(persisted) do
          {:ok, wire_projection} -> {:ok, wire_graph, wire_projection}
          {:error, reason} -> {:error, "topology_projection", reason}
        end

      {:error, reason} ->
        {:error, "graph_contract", reason}
    end
  end

  defp log_post_persist_wire_failure(stage, persisted, reason) do
    Logger.error("save_graph persisted but wire mapping failed",
      stage: stage,
      graph_id: persisted.id,
      graph_revision_id: persisted.revision_id,
      reason: wire_failure_fields(reason)
    )
  end

  # Log field names only. Changeset values may contain graph data.
  defp wire_failure_fields(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, _message} -> field end)
    |> Enum.uniq()
  end

  defp wire_failure_fields(reason) when is_atom(reason), do: reason
  defp wire_failure_fields(_reason), do: :unmapped_error

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
          {:ok, %{id: id}} ->
            {:reply,
             reply_fun.(
               "accepted",
               request.graph_revision_id,
               request.correlation_id,
               nil,
               id
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

  defp open_graph_reply(status, graph \\ nil, projection \\ nil) do
    contract_reply(OpenGraphReply, %{
      status: status,
      graph: graph,
      topology_projection: projection
    })
  end

  defp save_graph_reply(status, graph \\ nil, errors \\ [], projection \\ nil) do
    contract_reply(SaveGraphReply, %{
      status: status,
      graph: graph,
      topology_projection: projection,
      errors: errors
    })
  end

  defp graph_validation_errors(%Ecto.Changeset{
         changes: %{graph: %Ecto.Changeset{} = graph_changeset}
       }) do
    graph_errors(graph_changeset)
  end

  defp graph_validation_errors(_changeset), do: []

  defp graph_errors(changeset) do
    direct_errors(changeset, "graph", entity_id(changeset), []) ++
      embedded_errors(changeset, :nodes, "node") ++
      embedded_errors(changeset, :edges, "edge")
  end

  defp embedded_errors(changeset, field, kind) do
    changeset.changes
    |> Map.get(field, [])
    |> List.wrap()
    |> Enum.flat_map(&direct_errors(&1, kind, entity_id(&1), []))
  end

  defp direct_errors(changeset, kind, entity_id, path) do
    direct =
      Enum.flat_map(changeset.errors, fn {field, {message, options}} ->
        case Keyword.get(options, :nested_changeset) do
          %Ecto.Changeset{} = nested ->
            direct_errors(nested, kind, entity_id, path)

          _ ->
            [
              validation_error(
                kind,
                entity_id,
                path ++ [to_string(field)],
                format_error(message, options)
              )
            ]
        end
      end)

    nested =
      changeset.changes
      |> Enum.flat_map(fn
        {field, _nested} when kind == "graph" and field in [:nodes, :edges] ->
          []

        {field, %Ecto.Changeset{} = nested} ->
          direct_errors(nested, kind, entity_id, path ++ [to_string(field)])

        {field, nested} when is_list(nested) ->
          nested
          |> Enum.with_index()
          |> Enum.flat_map(fn
            {%Ecto.Changeset{} = nested, index} ->
              direct_errors(nested, kind, entity_id, path ++ [to_string(field), to_string(index)])

            {_value, _index} ->
              []
          end)

        {_field, _value} ->
          []
      end)

    direct ++ nested
  end

  defp validation_error(kind, entity_id, field_path, message) do
    %{entity_kind: kind, entity_id: entity_id, field_path: field_path, message: message}
  end

  defp entity_id(changeset), do: Ecto.Changeset.get_field(changeset, :id)

  defp format_error(message, options) do
    Enum.reduce(options, message, fn
      {key, value}, message when is_atom(key) ->
        String.replace(message, "%{#{key}}", format_error_option(value))

      _option, message ->
        message
    end)
  end

  defp format_error_option(value) when is_binary(value), do: value
  defp format_error_option(value) when is_atom(value), do: Atom.to_string(value)
  defp format_error_option(value) when is_number(value), do: to_string(value)
  defp format_error_option(value), do: inspect(value)

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

  defp describe_manifest_reply(status, plans, comparison_groups, errors) do
    contract_reply(DescribeManifestReply, %{
      status: status,
      plans: plans,
      comparison_groups: comparison_groups,
      errors: errors
    })
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

  defp project_topology_draft(params) do
    case ProjectTopologyDraftPayload.validate(params) do
      {:ok, request} ->
        draft_topology_projection(request)

      {:error, changeset} ->
        draft_reply(
          "invalid_graph",
          draft_request_document_id(changeset),
          draft_request_semantic_version(changeset),
          nil,
          draft_payload_errors(changeset)
        )
    end
  end

  # An invalid payload still carries correlation data. Preserve a usable request
  # identity and report both root payload errors and nested graph errors. Values
  # that the reply contract rejects stay nil.
  defp draft_request_document_id(%Ecto.Changeset{changes: changes}) do
    case Map.get(changes, :document_id) do
      value when is_binary(value) ->
        case Ecto.UUID.cast(value) do
          {:ok, _uuid} -> value
          :error -> nil
        end

      _value ->
        nil
    end
  end

  defp draft_request_semantic_version(%Ecto.Changeset{changes: changes}) do
    case Map.get(changes, :semantic_version) do
      value when is_integer(value) and value >= 0 -> value
      _value -> nil
    end
  end

  defp draft_payload_errors(changeset) do
    payload_errors(changeset) ++ graph_validation_errors(changeset)
  end

  # Root payload fields have no dedicated wire entity kind, so they use the
  # graph kind with no entity id.
  defp payload_errors(changeset) do
    Enum.flat_map(changeset.errors, fn {field, {message, options}} ->
      case Keyword.get(options, :nested_changeset) do
        %Ecto.Changeset{} ->
          []

        _none ->
          [
            validation_error(
              "graph",
              nil,
              [to_string(field)],
              format_error(message, options)
            )
          ]
      end
    end)
  end

  defp draft_topology_projection(request) do
    case GraphContract.to_domain(request.graph, validate_membership: false) do
      {:ok, %Graph{} = graph} ->
        case topology_projection(graph) do
          {:ok, projection} ->
            draft_reply(
              "ok",
              request.document_id,
              request.semantic_version,
              projection,
              []
            )

          {:error, _changeset} ->
            draft_reply(
              "unmapped_error",
              request.document_id,
              request.semantic_version,
              nil,
              []
            )
        end

      {:error, changeset} ->
        draft_reply(
          "invalid_graph",
          request.document_id,
          request.semantic_version,
          nil,
          direct_errors(changeset, "graph", entity_id(changeset), [])
        )
    end
  end

  defp draft_reply(status, document_id, semantic_version, projection, errors) do
    contract_reply(ProjectTopologyDraftReply, %{
      status: status,
      document_id: document_id,
      semantic_version: semantic_version,
      topology_projection: projection,
      errors: errors
    })
  end

  defp topology_projection(%Graph{} = graph) do
    graph
    |> TopologyProjection.project()
    |> TopologyProjectionContract.from_domain()
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
