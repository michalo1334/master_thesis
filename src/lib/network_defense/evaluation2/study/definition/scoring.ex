defmodule NetworkDefense.Evaluation2.Study.Definition.Scoring do
  @moduledoc false

  use Spectral

  alias NetworkDefense.Optimization.SimulationObjective
  alias NetworkDefense.Rules.Registry, as: RulesRegistry

  @type t :: %__MODULE__{
          objective: SimulationObjective.t(),
          monte_carlo_trials: pos_integer(),
          iterations_per_run: pos_integer(),
          max_attempts: pos_integer(),
          rules: [RulesRegistry.rule_type()]
        }
  defstruct [:objective, :monte_carlo_trials, :iterations_per_run, :max_attempts, :rules]
end
