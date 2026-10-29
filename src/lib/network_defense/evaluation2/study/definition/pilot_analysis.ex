defmodule NetworkDefense.Evaluation2.Study.Definition.PilotAnalysis do
  @moduledoc false

  use Spectral

  # The declared selection rule is lowest predicted runtime.
  @type t :: %__MODULE__{
          base_seed: non_neg_integer(),
          outer_subsamples: pos_integer(),
          target_half_width: float(),
          guard_quantile: float(),
          confidence_level: float(),
          bootstrap_replicates: pos_integer(),
          selection_rule: String.t()
        }
  defstruct [
    :base_seed,
    :outer_subsamples,
    :target_half_width,
    :guard_quantile,
    :confidence_level,
    :bootstrap_replicates,
    :selection_rule
  ]
end
