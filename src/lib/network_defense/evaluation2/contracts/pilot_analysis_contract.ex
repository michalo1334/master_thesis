defmodule NetworkDefense.Evaluation2.Contracts.PilotAnalysisContract do
  @moduledoc """
  Input and output contract of one Pilot analysis Gust run.

  The root input names the Pilot analysis phase. The terminal output carries the
  Pilot decision, the recommended candidate with its two sample counts, and the
  complete candidate summaries.
  """

  @behaviour NetworkDefense.Evaluation2.Contracts.PhaseContract

  alias NetworkDefense.Evaluation2.CandidateSummary
  alias NetworkDefense.Evaluation2.Contracts.PhaseContract
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.PilotOutcome

  defmodule Input do
    @moduledoc "Root input of one Pilot analysis run."

    @type t :: %__MODULE__{phase_id: Ecto.UUID.t()}

    defstruct [:phase_id]
  end

  defmodule Output do
    @moduledoc "Terminal output of one Pilot analysis run."

    @type t :: %__MODULE__{
            outcome: :recommended | :insufficient,
            candidate_id: PilotOutcome.candidate_id() | nil,
            plan_count_per_side: pos_integer() | nil,
            attacks_per_plan: pos_integer() | nil,
            candidate_summaries: [CandidateSummary.t()]
          }

    defstruct [
      :outcome,
      :candidate_id,
      :plan_count_per_side,
      :attacks_per_plan,
      :candidate_summaries
    ]
  end

  @doc "Encode the Pilot analysis phase identifier into Gust run params."
  @impl PhaseContract
  @spec to_params(Input.t()) :: PhaseContract.params()
  def to_params(_input), do: raise(NotImplementedError, function: :to_params)

  @doc "Decode the Pilot decision and its candidate summaries from the stored terminal result."
  @impl PhaseContract
  @spec decode_output!(PhaseContract.params()) :: Output.t()
  def decode_output!(_params), do: raise(NotImplementedError, function: :decode_output!)
end
