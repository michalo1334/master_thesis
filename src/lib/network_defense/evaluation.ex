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
    EvaluationRun,
    EvaluationRuns,
    Evaluator,
    OutputContract,
    Preflight
  }

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
      EvaluationManifests.upsert(Map.put(attrs, :content, content))
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

  @spec preflight(map()) ::
          {:ok, %{graph_revision_id: String.t(), entry_host_id: String.t()}} | {:error, [error()]}
  def preflight(manifest), do: Preflight.preflight(manifest)

  @spec input_content_digest(map()) :: String.t()
  def input_content_digest(content) do
    :crypto.hash(:sha256, :erlang.term_to_binary(content, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  @spec start(String.t()) :: {:ok, EvaluationRun.t()} | {:error, term()}
  def start(manifest_id) do
    with %EvaluationManifest{} = manifest <- EvaluationManifests.get_by_manifest_id(manifest_id),
         {:ok, content} <- ManifestContract.validate(manifest.content) do
      input_digest = input_content_digest(content)

      start_or_reuse(manifest, content, input_digest)
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  defp start_or_reuse(manifest, content, input_digest) do
    case EvaluationRuns.latest_for_manifest(manifest.id) do
      %EvaluationRun{input_digest: ^input_digest} = run ->
        {:ok, run}

      _latest_run ->
        start_new_run(manifest, content, input_digest)
    end
  end

  defp start_new_run(manifest, content, input_digest) do
    with {:ok, resolved} <- Preflight.preflight(content) do
      EvaluationRuns.create(%{
        evaluation_manifest_id: manifest.id,
        source_graph_revision_id: resolved.graph_revision_id,
        resolved_manifest: resolved_manifest(content, resolved),
        input_digest: input_digest
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
      nil -> {:error, :not_found}
      %EvaluationRun{status: status} = run when status in ["completed", "failed"] -> {:ok, run}
      %EvaluationRun{} = run -> run_evaluator(run)
    end
  end

  @spec report(String.t()) :: map() | nil
  def report(run_id) do
    case EvaluationRuns.get_with_manifest(run_id) do
      nil -> nil
      run -> EvaluationReport.generate(run)
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
