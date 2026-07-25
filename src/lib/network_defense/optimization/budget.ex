defmodule NetworkDefense.Optimization.Budget do
  @moduledoc """
  Type representing an optimization budget.

  For simplicity currently it's simply an integer. The budget in specific (currently not specified which ones) cases can be negative therefore integer, not non_neg_integer()
  """
  @type t :: integer()
end
