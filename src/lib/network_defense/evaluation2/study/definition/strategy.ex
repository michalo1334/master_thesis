defmodule NetworkDefense.Evaluation2.Study.Definition.Strategy do
  @moduledoc false

  alias NetworkDefense.DefenseActions.Registry, as: DefenseActionsRegistry
  alias NetworkDefense.Evaluation2.Study.Definition.Scoring
  alias NetworkDefense.Optimization.Contracts.OptimizationParams

  @type t :: %__MODULE__{
          key: OptimizationParams.strategy(),
          budget: pos_integer(),
          candidate_action_types: [DefenseActionsRegistry.action_type()],
          require_pre_attack_feasibility: boolean(),
          scoring: Scoring.t() | nil
        }
  defstruct [:key, :budget, :candidate_action_types, :require_pre_attack_feasibility, :scoring]
end
