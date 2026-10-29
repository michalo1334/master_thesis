defmodule NetworkDefense.Evaluation2.Study.Seed do
  @moduledoc false

  use Spectral

  # Seed value of one deterministic stream or one attack column.
  #
  # A seed stays a bare non-negative integer. The type names the role only, so
  # no wrapper struct and no conversion exist.

  @typedoc "One non-negative seed value."
  @type t :: non_neg_integer()
end
