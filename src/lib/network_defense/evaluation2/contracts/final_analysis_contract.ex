defmodule NetworkDefense.Evaluation2.Contracts.FinalAnalysisContract do
  @moduledoc false

  # Input and output contract of one Final analysis Gust run.
  #
  # The root input names the phase-run record and the accepted Final snapshot.
  # The terminal output holds the corrected comparison family of the declared
  # family.

  alias NetworkDefense.Evaluation2.CorrectedFamily
  alias NetworkDefense.Evaluation2.NotImplementedError

  defmodule Input do
    @moduledoc false

    # Root input of one Final analysis run.

    @type t :: %__MODULE__{
            phase_run_id: Ecto.UUID.t(),
            snapshot_id: Ecto.UUID.t()
          }

    defstruct [:phase_run_id, :snapshot_id]
  end

  defmodule Output do
    @moduledoc false

    # Terminal output of one Final analysis run.

    @type t :: %__MODULE__{family_result: CorrectedFamily.t()}

    defstruct [:family_result]
  end

  @spec to_params(Input.t()) :: map()
  def to_params(_input), do: raise(NotImplementedError, function: :to_params)

  @spec decode_output!(map()) :: Output.t()
  def decode_output!(_params), do: raise(NotImplementedError, function: :decode_output!)
end
