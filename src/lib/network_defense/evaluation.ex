defmodule NetworkDefense.Evaluation do
  @moduledoc """
  Public context for reproducible evaluation runs from a saved manifest.

  The dashboard and the local CLI use this context. It saves and lists
  manifests, validates and preflights them, and starts or resumes a run.

  The full multi-strategy evaluator is not implemented in this pass. The
  public seams are `start/1` and `resume/1`, which persist the run and its
  resolved source revision, and `run/1` which executes the evaluator. The
  evaluator is a stub that marks the run complete; wire the strategy loop
  into `Evaluator.run/2` to execute plans and trials.
  """

  alias NetworkDefense.Evaluation.Contracts.EvaluationManifest, as: ManifestContract

  alias NetworkDefense.Evaluation.{
    EvaluationManifest,
    EvaluationManifests,
    EvaluationReport,
    AnalysisResult,
    EvaluationRun,
    EvaluationRuns,
    AnalysisClient,
    Evaluator,
    OutputContract,
    PlanPreview,
    Preflight
  }

  alias NetworkDefense.Optimization.ModelVariant

  alias NetworkDefense.ReportProgress

  import Ecto.Query

  @type error :: %{path: String.t(), message: String.t()}

  @evaluation_events_topic "evaluation_events"

  @spec evaluation_events_topic() :: String.t()
  def evaluation_events_topic, do: @evaluation_events_topic

  @spec broadcast_progress(String.t(), map(), non_neg_integer(), pos_integer(), String.t()) :: :ok
  def broadcast_progress(run_id, graph, completed, total, detail) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @evaluation_events_topic,
      {:evaluation_progress,
       %{
         correlation_id: run_id,
         graph_id: graph.id,
         graph_revision_id: graph.revision_id,
         completed: completed,
         total: total,
         detail: detail
       }}
    )
  end

  @spec save(map()) :: {:ok, EvaluationManifest.t()} | {:error, term()}
  def save(attrs) do
    with {:ok, content} <- validate_content(attrs) do
      attrs = Map.put(attrs, :content, content)

      case Map.get(attrs, :existing_manifest_id) do
        nil -> EvaluationManifests.create(attrs)
        manifest_id -> update_manifest(manifest_id, attrs)
      end
    end
  end

  defp update_manifest(id, attrs) do
    case EvaluationManifests.get(id) do
      nil -> {:error, :not_found}
      manifest -> EvaluationManifests.update_manifest(manifest, attrs)
    end
  end

  @spec list() :: [EvaluationManifest.t()]
  def list, do: EvaluationManifests.list()

  @spec get(String.t()) :: EvaluationManifest.t() | nil
  def get(id), do: EvaluationManifests.get(id)

  @spec get_by_manifest_id(String.t()) :: EvaluationManifest.t() | nil
  def get_by_manifest_id(manifest_id), do: EvaluationManifests.get_by_manifest_id(manifest_id)

  @spec validate_content(map()) :: {:ok, map()} | {:error, [error()]}
  def validate_content(%{content: content}) when is_map(content) do
    ManifestContract.validate(content)
  end

  def validate_content(%{content: content}) when is_binary(content) do
    ManifestContract.parse(content)
  end

  def validate_content(_attrs), do: {:error, [%{path: "content", message: "is required"}]}

  @spec describe_manifest(map()) :: {:ok, map()} | {:error, [error()]}
  def describe_manifest(content) when is_map(content) do
    with {:ok, manifest} <- ManifestContract.validate(content) do
      {:ok, describe(manifest)}
    end
  end

  def describe_manifest(_), do: {:error, [%{path: "content", message: "must be a JSON object"}]}

  defp describe(manifest) do
    %{
      "plans" =>
        Enum.map(PlanPreview.plans(manifest), fn {model_variant, strategy, budget, selection_seed} ->
          %{
            "model_variant" => ModelVariant.to_wire(model_variant),
            "strategy" => strategy,
            "budget" => budget,
            "selection_seed" => selection_seed
          }
        end),
      "comparison_groups" =>
        PlanPreview.comparison_groups(manifest)
        |> NetworkDefense.Contracts.to_params()
    }
  end

  @spec preflight(map()) ::
          {:ok, %{graph_revision_id: String.t(), entry_host_id: String.t()}} | {:error, [error()]}
  def preflight(manifest), do: Preflight.preflight(manifest)

  @spec start(String.t()) :: {:ok, EvaluationRun.t()} | {:error, term()}
  def start(manifest_id) do
    with %EvaluationManifest{} = manifest <- EvaluationManifests.get_by_manifest_id(manifest_id),
         {:ok, content} <- ManifestContract.validate(manifest.content) do
      start_new_run(manifest, content)
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  defp start_new_run(manifest, content) do
    with {:ok, resolved} <- Preflight.preflight(content) do
      EvaluationRuns.create(%{
        evaluation_manifest_id: manifest.id,
        source_graph_revision_id: resolved.graph_revision_id,
        resolved_manifest: resolved_manifest(content, resolved)
      })
    end
  end

  @spec resume(String.t()) :: {:ok, EvaluationRun.t()} | {:error, term()}
  def resume(run_id) do
    case EvaluationRuns.get(run_id) do
      nil -> {:error, :not_found}
      %EvaluationRun{status: "completed"} = run -> {:ok, run}
      %EvaluationRun{} = run -> Evaluator.run(run)
    end
  end

  @spec run(String.t()) :: {:ok, EvaluationRun.t()} | {:error, term()}
  def run(run_id) do
    case EvaluationRuns.get(run_id) do
      nil ->
        {:error, :not_found}

      %EvaluationRun{status: status} = run when status in ["completed", "failed", "cancelled"] ->
        reannounce_terminal(run)
        {:ok, run}

      %EvaluationRun{} = run ->
        run_evaluator(run)
    end
  end

  def cancel(run_id) do
    with {:ok, run} <- EvaluationRuns.cancel(run_id) do
      cancel_children(NetworkDefense.Simulation.Experiment, run_id)
      NetworkDefense.Optimization.OptimizationRuns.cancel_by_evaluation(run_id)

      Oban.cancel_all_jobs(
        from(j in Oban.Job,
          where: j.worker == ^"NetworkDefense.Evaluation.EvaluationWorker",
          where: fragment("? @> ?", j.args, ^%{"run_id" => run_id})
        )
      )

      {:ok, run}
    end
  end

  defp cancel_children(experiments, run_id) do
    import Ecto.Query

    experiments
    |> where([e], e.evaluation_run_id == ^run_id and e.status == "running")
    |> NetworkDefense.Repo.update_all(set: [status: "cancelled", updated_at: DateTime.utc_now()])
  end

  # Re-announcing a terminal result keeps listeners (the dashboard) in sync when
  # a completed run is requested again.
  defp reannounce_terminal(%EvaluationRun{status: "completed"} = run) do
    broadcast_completed(run)
  end

  defp reannounce_terminal(%EvaluationRun{status: "failed"} = run) do
    broadcast_failed(run)
  end

  defp reannounce_terminal(%EvaluationRun{status: "cancelled"}), do: :ok

  @spec report(String.t(), ReportProgress.progress_callback()) :: map() | nil
  def report(run_id, on_progress \\ ReportProgress.noop()) do
    case EvaluationRuns.get_with_manifest(run_id) do
      nil -> nil
      run -> EvaluationReport.generate(run, on_progress)
    end
  end

  @spec download_archive(String.t()) ::
          {:ok, binary(), String.t()} | {:error, :not_found | :incomplete | term()}
  def download_archive(run_id) do
    case EvaluationRuns.get(run_id) do
      nil -> {:error, :not_found}
      %EvaluationRun{status: "completed"} = run -> OutputContract.archive(run)
      %EvaluationRun{} -> {:error, :incomplete}
    end
  end

  @spec analyze(String.t(), :pilot | :analyze | String.t()) ::
          {:ok, binary()} | {:error, term()}
  def analyze(run_id, mode) when mode in [:pilot, :analyze, "pilot", "analyze"] do
    with {:ok, archive, _filename} <- download_archive(run_id) do
      AnalysisClient.analyze(archive, run_id, mode)
    end
  end

  def analyze(_run_id, _mode), do: {:error, :invalid_mode}

  @spec parse_analysis(binary()) :: {:ok, map()} | {:error, term()}
  def parse_analysis(response) when is_binary(response) do
    config = Application.get_env(:network_defense, :analysis_service, [])
    AnalysisResult.parse(response, config[:max_zip_bytes] || 50_000_000)
  end

  defp run_evaluator(run) do
    case Evaluator.run(run) do
      {:ok, %{status: "completed"} = completed} ->
        broadcast_completed(completed)
        {:ok, completed}

      {:ok, %{status: "failed"} = failed} ->
        broadcast_failed(failed)
        {:ok, failed}

      other ->
        other
    end
  end

  defp broadcast_completed(%EvaluationRun{} = run) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @evaluation_events_topic,
      {:evaluation_completed, completed_payload(run)}
    )
  end

  defp broadcast_failed(%EvaluationRun{} = run) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @evaluation_events_topic,
      {:evaluation_failed, failed_payload(run)}
    )
  end

  defp completed_payload(%EvaluationRun{} = run) do
    manifest = manifest_for(run)

    %{
      run_id: run.id,
      manifest_id: manifest.manifest_id,
      manifest_title: manifest.title,
      source_graph_revision_id: run.source_graph_revision_id
    }
  end

  defp failed_payload(%EvaluationRun{} = run) do
    manifest = manifest_for(run)

    %{
      run_id: run.id,
      manifest_id: manifest.manifest_id,
      manifest_title: manifest.title,
      reason: run.failure_reason || :internal_error
    }
  end

  defp manifest_for(%EvaluationRun{evaluation_manifest: %Ecto.Association.NotLoaded{}} = run) do
    case EvaluationRuns.get_with_manifest(run.id) do
      %EvaluationRun{evaluation_manifest: manifest} -> manifest
      _ -> %EvaluationManifest{manifest_id: "", title: ""}
    end
  end

  defp manifest_for(%EvaluationRun{evaluation_manifest: manifest}), do: manifest

  defp resolved_manifest(manifest, resolved) do
    manifest
    |> Map.put("source", %{
      "type" => "graph_revision",
      "graph_revision_id" => resolved.graph_revision_id
    })
    |> Map.put("attacker", %{
      "entry_host" => %{"type" => "node_id", "value" => resolved.entry_host_id},
      "max_attempts" => get_in(manifest, ["attacker", "max_attempts"])
    })
  end
end
