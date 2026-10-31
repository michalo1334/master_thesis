defmodule NetworkDefense.Evaluation2.Study.Definition.Candidate do
  @moduledoc false

  use Spectral

  # One declared Pilot sample-size candidate. Plans and attacks stay a pair,
  # so separate lists cannot form an implicit candidate grid.

  @type t :: %__MODULE__{id: String.t(), plans: pos_integer(), attacks: pos_integer()}
  defstruct [:id, :plans, :attacks]
end
