defmodule NetworkDefense.Evaluation2.Study.Definition.SampleSize do
  @moduledoc false

  use Spectral

  # One ordered pair of plan and attack counts. Capacity uses non-negative
  # counts: an empty extra pool is valid, a candidate is not.

  @type t :: %__MODULE__{plans: non_neg_integer(), attacks: non_neg_integer()}
  defstruct [:plans, :attacks]
end
