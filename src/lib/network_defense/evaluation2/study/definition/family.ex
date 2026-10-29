defmodule NetworkDefense.Evaluation2.Study.Definition.Family do
  @moduledoc false

  alias NetworkDefense.Evaluation2.Study.Definition.Comparison

  # The declared method is Holm; its string remains part of the definition format.
  @type t :: %__MODULE__{
          id: String.t(),
          method: String.t(),
          alpha: float(),
          comparisons: [Comparison.t()]
        }
  defstruct [:id, :method, :alpha, :comparisons]
end
