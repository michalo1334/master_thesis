defmodule NetworkDefense.Evaluation2.Contracts.PilotCollectionContract do
  @moduledoc """
  Input and output contract of one Pilot collection Gust run.

  The root input names the Pilot collection phase. The terminal output carries the
  identifier of the accepted Pilot evidence snapshot.
  """

  @behaviour NetworkDefense.Evaluation2.Contracts.PhaseContract

  alias NetworkDefense.Evaluation2.Contracts.PhaseContract
  alias NetworkDefense.Evaluation2.NotImplementedError

  defmodule Input do
    @moduledoc "Root input of one Pilot collection run."

    @type t :: %__MODULE__{phase_id: Ecto.UUID.t()}

    defstruct [:phase_id]
  end

  defmodule Output do
    @moduledoc "Terminal output of one Pilot collection run."

    @type t :: %__MODULE__{snapshot_id: Ecto.UUID.t()}

    defstruct [:snapshot_id]
  end

  @doc "Encode the Pilot collection phase identifier into Gust run params."
  @impl PhaseContract
  @spec to_params(Input.t()) :: PhaseContract.params()
  def to_params(_input), do: raise(NotImplementedError, function: :to_params)

  @doc "Decode the accepted Pilot snapshot identifier from the stored terminal result."
  @impl PhaseContract
  @spec decode_output!(PhaseContract.params()) :: Output.t()
  def decode_output!(_params), do: raise(NotImplementedError, function: :decode_output!)
end
