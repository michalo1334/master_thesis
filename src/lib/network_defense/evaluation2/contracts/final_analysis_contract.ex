defmodule NetworkDefense.Evaluation2.Contracts.FinalAnalysisContract do
  @moduledoc """
  Input and output contract of one Final analysis Gust run.

  The root input names the Final analysis phase, whose loader resolves the
  accepted Final snapshot and collection aggregate. The terminal output carries
  the corrected comparison family.
  """

  @behaviour NetworkDefense.Evaluation2.Contracts.PhaseContract

  alias NetworkDefense.Evaluation2.Contracts.PhaseContract
  alias NetworkDefense.Evaluation2.{CorrectedFamily, NotImplementedError}

  defmodule Input do
    @moduledoc "Root input of one Final analysis run."

    @type t :: %__MODULE__{phase_id: Ecto.UUID.t()}

    defstruct [:phase_id]
  end

  defmodule Output do
    @moduledoc "Terminal output of one Final analysis run."

    @type t :: %__MODULE__{family_result: CorrectedFamily.t()}

    defstruct [:family_result]
  end

  @doc "Encode the Final analysis phase identifier into Gust run params."
  @impl PhaseContract
  @spec to_params(Input.t()) :: PhaseContract.params()
  def to_params(_input), do: raise(NotImplementedError, function: :to_params)

  @doc "Decode the corrected comparison family from the stored terminal result."
  @impl PhaseContract
  @spec decode_output!(PhaseContract.params()) :: Output.t()
  def decode_output!(_params), do: raise(NotImplementedError, function: :decode_output!)
end
