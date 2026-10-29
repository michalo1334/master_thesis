defmodule NetworkDefense.Evaluation2.Study.Result.Comparison.Adjustment do
  @moduledoc """
  Family adjustment of one comparison.
  """

  use Spectral

  @type t :: %__MODULE__{
          adjusted_p_value: float(),
          reject_null: boolean()
        }

  defstruct [:adjusted_p_value, :reject_null]
end
