defmodule NetworkDefense.Evaluation2.Study.Result.Family do
  @moduledoc """
  Corrected Final comparison family of one study result.

  The envelope names the declared family, the fixed correction method, and the
  declared alpha. The comparisons follow the declared family order.

  The family size is the number of comparisons, so `size/1` derives it.
  """

  alias NetworkDefense.Evaluation2.Study.Result.Comparison

  @typedoc "Correction method of the Final analysis."
  @type method :: :holm

  @type t :: %__MODULE__{
          id: String.t(),
          method: method(),
          alpha: float(),
          comparisons: [Comparison.t()]
        }

  defstruct [:id, :method, :alpha, :comparisons]

  @doc "Return the number of declared comparisons."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{comparisons: comparisons}), do: length(comparisons)
end
