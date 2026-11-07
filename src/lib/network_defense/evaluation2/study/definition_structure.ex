defmodule NetworkDefense.Evaluation2.Study.DefinitionStructure do
  @moduledoc """
  Derived structure of one frozen definition.

  The values are counts and capacities that construction derives from the
  declared settings. They describe the study shape for inspection, rather than
  adding an operator setting. `comparisons` counts the declared
  alternative-versus-CVSS family members, and `collection_groups` counts the
  distinct tier/budget/strategy groups behind them.

  `pilot_plans` and `pilot_attacks` are the collected Pilot capacities: the
  coordinate-wise largest candidate plus the declared extra pool.
  """

  use Spectral

  @type t :: %__MODULE__{
          comparisons: non_neg_integer(),
          collection_groups: non_neg_integer(),
          pilot_plans: pos_integer(),
          pilot_attacks: pos_integer()
        }

  defstruct [:comparisons, :collection_groups, :pilot_plans, :pilot_attacks]
end
