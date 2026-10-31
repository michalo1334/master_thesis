defmodule NetworkDefense.Evaluation2.Study.Definition.Scoring do
  @moduledoc false

  use Spectral

  alias NetworkDefense.Optimization.SimulationObjective

  # Strategy-specific scoring settings. The simulation model itself belongs to
  # the study, so this value declares only the objective and the trial budget.

  @type t :: %__MODULE__{
          objective: SimulationObjective.t(),
          monte_carlo_trials: pos_integer()
        }
  defstruct [:objective, :monte_carlo_trials]
end
