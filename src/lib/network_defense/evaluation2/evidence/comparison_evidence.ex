defmodule NetworkDefense.Evaluation2.Evidence.ComparisonEvidence do
  @moduledoc """
  Aligned evidence matrices of one declared comparison.

  One row belongs to one selected plan. One column belongs to one attack seed of
  the shared attack-column list. A cell holds the observed mission impact of that
  attack on that plan.

  The identity names the network-size tier. The matrices are plain
  `NetworkDefense.Evaluation2.Matrix` values, so both sides share one column list.
  """

  alias NetworkDefense.Evaluation2.ComparisonIdentity
  alias NetworkDefense.Evaluation2.{Matrix, Seed}

  @type t :: %__MODULE__{
          identity: ComparisonIdentity.t(),
          attack_seeds: [Seed.t()],
          alternative: Matrix.t(),
          reference: Matrix.t()
        }

  defstruct [:identity, :attack_seeds, :alternative, :reference]
end
