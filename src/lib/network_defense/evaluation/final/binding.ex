defmodule NetworkDefense.Evaluation.Final.Binding do
  @moduledoc false

  alias NetworkDefense.Evaluation.EvidenceSnapshots

  alias NetworkDefense.Evaluation.Final.Contracts.{
    FinalError,
    Request,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Final.Limits
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.{FinalBindingContext, FinalSource}
  alias NetworkDefense.Evaluation.StudyPhase

  # Cross-record binding guard for persisted Final requests.
  #
  # Snapshot create paths enforce the JSON encoded-size cap before insert.
  # Binding and read paths trust persisted PostgreSQL JSONB for size.
  # They do not re-encode payloads or compare byte counts.
  #
  # Preparation, each mapped member, fan-in, and public result read-back are
  # distinct trust boundaries. Binding repeats the contract, metadata, source,
  # family, order, and count checks at each boundary.

  @type option :: {:limits, boolean()}

  @doc """
  Verify one low-level Final request or one frozen study lifecycle source.

  Low-level verification returns the parsed snapshot payload. Lifecycle
  verification reloads the execution and returns its accepted Pilot phase.
  """
  def verify(request_or_execution_id, options_or_source \\ [])

  @spec verify(Request.t(), [option()]) :: {:ok, SnapshotPayload.t()} | {:error, FinalError.t()}
  def verify(%Request{} = request, options) when is_list(options) do
    with {:ok, snapshot, payload} <- EvidenceSnapshots.load_final(request.snapshot_id),
         :ok <- Request.matches_snapshot(request, snapshot, payload),
         :ok <- check_limits(request, options),
         :ok <- verify_lifecycle_source(request) do
      {:ok, payload}
    end
  end

  @spec verify(Ecto.UUID.t(), FinalSource.t()) ::
          {:ok, StudyPhase.t()} | {:error, StudyError.t()}
  def verify(execution_id, %FinalSource{} = source) do
    with {:ok, context} <- FinalBindingContext.load(execution_id),
         :ok <- FinalSource.compare(source, context) do
      {:ok, context.accepted_pilot_phase}
    end
  end

  defp verify_lifecycle_source(%Request{} = request) do
    case FinalBindingContext.load_for_analysis(request.study_execution_id) do
      {:ok, context} -> compare_request_source(request, context)
      {:error, %StudyError{}} -> {:error, FinalError.changed_pilot_source()}
    end
  end

  defp compare_request_source(%Request{} = request, context) do
    selection = context.selection
    definition = context.definition
    pilot_phase = context.accepted_pilot_phase
    final_collection_phase = context.accepted_final_collection_phase

    comparisons =
      Enum.map(definition.family.comparisons, fn comparison ->
        {
          comparison.tier,
          comparison.budget,
          Atom.to_string(comparison.alternative),
          Atom.to_string(comparison.reference),
          comparison.outcome
        }
      end)

    requested =
      Enum.map(request.expected_comparisons, fn comparison ->
        {
          comparison.tier,
          comparison.budget,
          comparison.alternative,
          comparison.reference,
          comparison.outcome
        }
      end)

    if request.study_revision_id == context.execution.study_revision_id and
         request.family_id == definition.family.id and
         request.plan_count == selection.plan_count_per_side and
         request.attacks_per_plan == selection.attacks_per_plan and
         request.source_pilot_run_id == pilot_phase.gust_run_id and
         request.snapshot_id == final_collection_phase.snapshot_id and
         requested == comparisons do
      :ok
    else
      {:error, FinalError.changed_pilot_source()}
    end
  end

  defp check_limits(%Request{} = request, options) do
    if Keyword.get(options, :limits, true) do
      Limits.validate(request)
    else
      :ok
    end
  end
end
