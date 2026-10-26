defmodule NetworkDefense.Evaluation.Final.Binding do
  @moduledoc false

  alias NetworkDefense.Evaluation.EvidenceSnapshots

  alias NetworkDefense.Evaluation.Final.Contracts.{
    FinalError,
    Request,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Final.{Limits, Source}
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
         {:ok, pilot} <- Source.require_recommended_pilot(request.source_pilot_run_id),
         :ok <- Request.matches_pilot(request, pilot) do
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

  defp check_limits(%Request{} = request, options) do
    if Keyword.get(options, :limits, true) do
      Limits.validate(request)
    else
      :ok
    end
  end
end
