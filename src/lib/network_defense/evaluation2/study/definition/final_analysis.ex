defmodule NetworkDefense.Evaluation2.Study.Definition.FinalAnalysis do
  @moduledoc false

  # The declared test alternative is two-sided.
  @type t :: %__MODULE__{
          comparison_seeds: [non_neg_integer()],
          alpha: float(),
          confidence_level: float(),
          test_alternative: String.t(),
          bootstrap_replicates: pos_integer()
        }
  defstruct [
    :comparison_seeds,
    :alpha,
    :confidence_level,
    :test_alternative,
    :bootstrap_replicates
  ]
end
