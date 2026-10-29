defmodule NetworkDefense.Evaluation2.Study.Final.ComparisonJob do
  @moduledoc false

  # One mapped Final analysis job.
  #
  # A job identifies one declared comparison by position. Family identity,
  # analysis settings, and the accepted evidence stay in application records that
  # the task loads.

  @type t :: %__MODULE__{comparison_position: non_neg_integer()}

  defstruct [:comparison_position]
end
