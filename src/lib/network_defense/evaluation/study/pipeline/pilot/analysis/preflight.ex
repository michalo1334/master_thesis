defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Preflight do
  @moduledoc false

  alias NetworkDefense.Evaluation.EvidenceSnapshots
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Contracts.PilotRequest
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Work
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Error, as: PilotError

  # Checks the declared request against the stored snapshot before a Gust run
  # exists.
  #
  # The public API already validated both. A resumed execution re-reads them, so
  # the checks run again inside the stage.

  @spec validate(PilotRequest.t()) :: :ok | {:error, PilotError.t()}
  def validate(%PilotRequest{} = request) do
    with {:ok, snapshot, payload} <- EvidenceSnapshots.load(request.snapshot_id),
         :ok <- PilotRequest.matches_snapshot(request, snapshot, payload) do
      Work.preflight(request, payload)
    end
  end
end
