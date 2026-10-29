defmodule NetworkDefense.Evaluation2.Study.Pilot.Analyze do
  @moduledoc """
  Candidate assessment of the Pilot phase.

  Preparation turns the declared candidate grid and the declared family into one
  job per candidate and comparison pair. Each job assesses the accepted Pilot
  evidence of one comparison through the bounded precision estimate.

  The compute boundary owns strict type and shape checks. The assessment owns the
  informativeness and precision decision of its candidate and comparison.
  """

  alias NetworkDefense.Evaluation2.{CandidateAssessment, PilotJob}
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Study.Definition

  @doc """
  Prepare the Pilot analysis jobs of one definition.

  Job positions follow the declared candidate order and the declared family
  order. The derived stream seed makes the historical Pilot stream reproducible.
  """
  @spec prepare(Definition.t()) :: [PilotJob.t()]
  def prepare(_definition), do: raise(NotImplementedError, function: :prepare)

  @doc """
  Assess one candidate and comparison pair against the accepted Pilot snapshot.

  The assessment passes when every outer subsample is informative and the guarded
  half-width stays within the declared target.
  """
  @spec run(Ecto.UUID.t(), PilotJob.t()) :: CandidateAssessment.t()
  def run(_phase_id, _job), do: raise(NotImplementedError, function: :run)
end
