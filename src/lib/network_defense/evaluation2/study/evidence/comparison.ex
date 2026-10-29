defmodule NetworkDefense.Evaluation2.Study.Evidence.Comparison do
  @moduledoc false

  # Aligned evidence matrices of one declared comparison.
  #
  # One row belongs to one selected plan. One column belongs to one attack seed
  # of the shared attack-column list. A cell holds the observed mission impact of
  # that attack on that plan.
  #
  # The identity of the comparison stays in the immutable definition, so this
  # value carries observations only.

  alias NetworkDefense.Evaluation2.Study.Matrix
  alias NetworkDefense.Evaluation2.Study.Seed

  @type t :: %__MODULE__{
          attack_seeds: [Seed.t()],
          alternative: Matrix.t(),
          reference: Matrix.t()
        }

  defstruct [:attack_seeds, :alternative, :reference]
end
