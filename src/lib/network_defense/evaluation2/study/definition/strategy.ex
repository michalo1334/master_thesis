defmodule NetworkDefense.Evaluation2.Study.Definition.Strategy do
  @moduledoc false

  use Spectral

  alias NetworkDefense.Evaluation2.Study.Definition.Scoring
  alias NetworkDefense.Optimization.Contracts.OptimizationParams

  # One declared plan-selection alternative of a tier.
  #
  # The variant that carries scoring data is a scored alternative; every other
  # primary kind leaves `scoring` nil. Budget, permitted actions, and
  # feasibility are owned by the tier and the study policy.

  @type t :: %__MODULE__{
          key: OptimizationParams.strategy(),
          scoring: Scoring.t() | nil
        }
  defstruct [:key, :scoring]
end
