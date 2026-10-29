defmodule NetworkDefense.Evaluation2.Study.Definition.Simulation do
  @moduledoc false

  alias NetworkDefense.Rules.Registry, as: RulesRegistry

  @type t :: %__MODULE__{
          iterations_per_run: pos_integer(),
          max_attempts: pos_integer(),
          rules: [RulesRegistry.rule_type()],
          require_pre_attack_feasibility: boolean()
        }
  defstruct [:iterations_per_run, :max_attempts, :rules, :require_pre_attack_feasibility]
end
