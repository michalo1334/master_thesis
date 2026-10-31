defmodule NetworkDefense.Evaluation2.Study.Result.Comparison.Test do
  @moduledoc """
  Two-sided test of one comparison.
  """

  use Spectral

  @typedoc "Test method of the comparison contract."
  @type method :: :sign_conservative_betting

  @typedoc "Alternative hypothesis of the test."
  @type alternative :: :two_sided

  @type t :: %__MODULE__{
          method: method(),
          alternative: alternative(),
          raw_p_value: float()
        }

  defstruct [:method, :alternative, :raw_p_value]
end
