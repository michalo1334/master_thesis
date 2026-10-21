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
  # Submission checks the snapshot metadata, the snapshot byte count, the
  # declared order, the resource caps, and the actual source Pilot. A Final run
  # outlives those checks: preparation, every mapped member, the fan-in, and the
  # public result read each load the persisted request again. Each of those
  # boundaries therefore repeats the same binding, so a metadata-only snapshot
  # change or a Pilot that stopped being recommended cannot pass a later
  # boundary.
  #
  # The guard compares contracts and relations only. A relation-preserving
  # content change inside one payload stays invisible, because the snapshot
  # stores a byte count and no hash.

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
