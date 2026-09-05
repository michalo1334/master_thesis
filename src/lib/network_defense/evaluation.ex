defmodule NetworkDefense.Evaluation do
  @moduledoc """
  Public context for reproducible evaluation runs from a saved manifest.

  The dashboard and the local CLI use this context. It saves and lists
  manifests, validates and preflights them, and starts or resumes a run.

  `start/1` and `resume/1` persist a run and its resolved source revision.
  `run/1` executes the manifest-declared plans and attack trials.
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

  @spec import_manifest(String.t(), String.t() | nil) ::
          {:ok, %{manifest_id: String.t(), title: String.t(), status: String.t()}}
          | {:error, [error()] | :conflict}
  def import_manifest(json, title \\ nil) when is_binary(json) do
    case validate_content(%{content: json}) do
      {:ok, content} -> import_content(content, title)
      error -> error
    end
  end

  defp import_content(content, title) do
    id = content["id"]

    case EvaluationManifests.get_by_manifest_id(id) do
      nil ->
        case save(%{manifest_id: id, title: title || id, content: content}) do
          {:ok, _manifest} -> {:ok, %{manifest_id: id, title: title || id, status: "imported"}}
          error -> manifest_id_conflict(error, :conflict)
        end

      %EvaluationManifest{} = existing when content == existing.content ->
        {:ok, %{manifest_id: id, title: existing.title, status: "reused"}}

      %EvaluationManifest{} ->
        {:error, :conflict}
    end
  end

  @spec freeze(String.t(), String.t(), String.t() | nil) ::
          {:ok,
           %{
             source_manifest_id: String.t(),
             target_manifest_id: String.t(),
             graph_revision_id: String.t(),
             entry_host_id: String.t()
           }}
          | {:error,
             [error()]
             | :invalid_target_manifest_id
             | :invalid_title
             | :not_found
             | :target_exists
             | :source_not_topology}
  def freeze(source_manifest_id, target_manifest_id, title \\ nil)

  def freeze(source_manifest_id, target_manifest_id, title)
      when is_binary(source_manifest_id) and is_binary(target_manifest_id) do
    title = title || target_manifest_id

    with %EvaluationManifest{} = source <-
           EvaluationManifests.get_by_manifest_id(source_manifest_id),
         :ok <- valid_target_manifest_id(target_manifest_id),
         :ok <- valid_title(title),
         :ok <- reject_existing_target(target_manifest_id),
         {:ok, content} <- ManifestContract.validate(source.content),
         :ok <- require_topology_source(content),
         {:ok, resolved} <- Preflight.preflight(content),
         frozen = resolved_manifest(content, resolved) |> Map.put("id", target_manifest_id),
         {:ok, _manifest} <- save_frozen_manifest(target_manifest_id, title, frozen) do
      {:ok,
       %{
         source_manifest_id: source_manifest_id,
         target_manifest_id: target_manifest_id,
         graph_revision_id: resolved.graph_revision_id,
         entry_host_id: resolved.entry_host_id
       }}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def freeze(_source_manifest_id, _target_manifest_id, _title),
    do: {:error, :invalid_target_manifest_id}

  defp save_frozen_manifest(target_manifest_id, title, frozen) do
    save(%{manifest_id: target_manifest_id, title: title, content: frozen})
    |> manifest_id_conflict(:target_exists)
  end

  defp manifest_id_conflict({:error, %Ecto.Changeset{} = changeset} = error, replacement) do
    if Enum.any?(changeset.errors, fn {field, {_message, options}} ->
         field == :manifest_id and options[:constraint] == :unique
       end),
       do: {:error, replacement},
       else: error
  end

  defp manifest_id_conflict(result, _replacement), do: result

  defp valid_target_manifest_id(value)
       when is_binary(value) and byte_size(value) in 1..255,
       do: :ok

  defp valid_target_manifest_id(_value), do: {:error, :invalid_target_manifest_id}

  defp valid_title(value) when is_binary(value) and byte_size(value) in 1..255, do: :ok
  defp valid_title(_value), do: {:error, :invalid_title}

  defp reject_existing_target(target_manifest_id) do
    case EvaluationManifests.get_by_manifest_id(target_manifest_id) do
      nil -> :ok
      _manifest -> {:error, :target_exists}
    end
  end

  defp require_topology_source(%{"source" => %{"type" => "topology"}}), do: :ok
  defp require_topology_source(_), do: {:error, :source_not_topology}

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

  defp start_new_run(manifest, content, purpose \\ "evaluation") do
    with {:ok, resolved} <- Preflight.preflight(content) do
      EvaluationRuns.create(%{
        evaluation_manifest_id: manifest.id,
        source_graph_revision_id: resolved.graph_revision_id,
        resolved_manifest: resolved_manifest(content, resolved),
        purpose: purpose
      })
    end
  end

  @spec warm_up(String.t()) :: {:ok, EvaluationRun.t()} | {:error, term()}
  def warm_up(manifest_id) do
    with %EvaluationManifest{} = manifest <- EvaluationManifests.get_by_manifest_id(manifest_id),
         {:ok, content} <- ManifestContract.validate(manifest.content),
         {:ok, run} <- start_new_run(manifest, content, "warmup") do
      run_evaluator(run)
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
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
    |> where([e], e.evaluation_run_id == ^run_id and e.status == :running)
    |> NetworkDefense.Repo.update_all(set: [status: :cancelled, updated_at: DateTime.utc_now()])
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

  def resolved_manifest(manifest, resolved) do
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
