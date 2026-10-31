defmodule NetworkDefense.Evaluation2.Study.Definition.Simulation do
  @moduledoc false

  use Spectral

  alias NetworkDefense.Rules.Registry, as: RulesRegistry

  # One study-level simulation model. Scoring and evidence collection execute
  # the same declared model; only objectives and scoring effort are
  # strategy-specific.

  @type t :: %__MODULE__{
          iterations_per_run: pos_integer(),
          max_attempts: pos_integer(),
          rules: [RulesRegistry.rule_type()]
        }
  defstruct [:iterations_per_run, :max_attempts, :rules]
end
