defmodule NetworkDefense.Evaluation.Final.Binding do
  @moduledoc false

  alias NetworkDefense.Evaluation.EvidenceSnapshots

  alias NetworkDefense.Evaluation.Final.Contracts.{
    FinalError,
    Request,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Final.{Limits, Source}

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
  Verify the stored snapshot and the source Pilot of one persisted request.

  Returns the parsed stored payload. `:limits` is enabled by default; the
  result read-back boundary disables it because it performs no compute.
  """
  @spec verify(Request.t(), [option()]) :: {:ok, SnapshotPayload.t()} | {:error, FinalError.t()}
  def verify(%Request{} = request, options \\ []) do
    with {:ok, snapshot, payload} <- EvidenceSnapshots.load_final(request.snapshot_id),
         :ok <- Request.matches_snapshot(request, snapshot, payload),
         :ok <- check_limits(request, options),
         {:ok, pilot} <- Source.require_recommended_pilot(request.source_pilot_run_id),
         :ok <- Request.matches_pilot(request, pilot) do
      {:ok, payload}
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
