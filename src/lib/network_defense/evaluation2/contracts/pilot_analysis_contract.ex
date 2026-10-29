defmodule NetworkDefense.Evaluation2.Contracts.PilotAnalysisContract do
  @moduledoc false

  # Input and output contract of one Pilot analysis Gust run.
  #
  # The root input names the phase-run record and the accepted Pilot snapshot.
  # The terminal output holds the compact Pilot outcome and the complete
  # candidate summaries. The lifecycle stores the outcome only, so the detailed
  # summaries stay in the terminal Gust result.

  alias NetworkDefense.Evaluation2.CandidateSummary
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Study.PilotOutcome

  defmodule Input do
    @moduledoc false

    # Root input of one Pilot analysis run.

    @type t :: %__MODULE__{
            phase_run_id: Ecto.UUID.t(),
            snapshot_id: Ecto.UUID.t()
          }

    defstruct [:phase_run_id, :snapshot_id]
  end

  defmodule Output do
    @moduledoc false

    # Terminal output of one Pilot analysis run.

    @type t :: %__MODULE__{
            outcome: PilotOutcome.t(),
            candidates: [CandidateSummary.t()]
          }

    defstruct [:outcome, :candidates]
  end

  @spec to_params(Input.t()) :: map()
  def to_params(_input), do: raise(NotImplementedError, function: :to_params)

  @spec decode_output!(map()) :: Output.t()
  def decode_output!(_params), do: raise(NotImplementedError, function: :decode_output!)
end
