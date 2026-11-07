defmodule NetworkDefense.Evaluation2.Study.StrategyOption do
  @moduledoc """
  One selectable plan-selection alternative of a study revision.

  `value` is the optimization wire identifier. `scoring_required` states whether
  the alternative declares an objective and a Monte Carlo trial count.
  `action_types` lists the defense actions that the strategy supports, so the
  authoring form can present the shared action policy against the alternatives
  that a tier declares.

  The implicit CVSS reference is not an alternative, so it carries no option.
  """

  use Spectral

  @type t :: %__MODULE__{
          value: String.t(),
          scoring_required: boolean(),
          action_types: [String.t()]
        }

  defstruct [:value, :scoring_required, :action_types]
end
