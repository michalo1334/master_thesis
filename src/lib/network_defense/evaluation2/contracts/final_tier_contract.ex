defmodule NetworkDefense.Evaluation2.Contracts.FinalTierContract do
  @moduledoc """
  Input and output contract of one Final tier collection Gust run.

  The root input names the phase-run record, which owns the execution, the study
  tier, and the Gust run. The terminal output repeats the tier identity and lists
  the measured replica positions. Tier order comes from the closed
  `NetworkDefense.Evaluation2.Tier` order, so neither side carries a position.
  """

  @behaviour NetworkDefense.Evaluation2.Contracts.PhaseContract

  alias NetworkDefense.Evaluation2.Contracts.PhaseContract
  alias NetworkDefense.Evaluation2.{NotImplementedError, Tier}

  defmodule Input do
    @moduledoc "Root input of one Final tier collection run."

    @type t :: %__MODULE__{phase_run_id: Ecto.UUID.t()}

    defstruct [:phase_run_id]
  end

  defmodule Output do
    @moduledoc "Terminal output of one Final tier collection run."

    @type t :: %__MODULE__{
            tier: Tier.t(),
            measured_positions: [non_neg_integer()]
          }

    defstruct [:tier, :measured_positions]
  end

  @doc "Encode the Final tier phase-run identifier into Gust run params."
  @impl PhaseContract
  @spec to_params(Input.t()) :: PhaseContract.params()
  def to_params(_input), do: raise(NotImplementedError, function: :to_params)

  @doc "Decode the tier identity and the measured positions from the stored terminal result."
  @impl PhaseContract
  @spec decode_output!(PhaseContract.params()) :: Output.t()
  def decode_output!(_params), do: raise(NotImplementedError, function: :decode_output!)
end
