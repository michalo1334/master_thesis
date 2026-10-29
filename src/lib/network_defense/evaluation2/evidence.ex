defmodule NetworkDefense.Evaluation2.Evidence do
  @moduledoc """
  Accepted evidence of one study phase.

  Evidence holds one comparison entry per declared family member, in declared
  order. Both sides of every comparison share one attack-column list of
  `NetworkDefense.Evaluation2.Seed` values, and each side is one
  `NetworkDefense.Evaluation2.Matrix`. A later analysis therefore reads aligned
  matrices without rebuilding them.
  """

  alias NetworkDefense.Evaluation2.Evidence.ComparisonEvidence

  @type role :: :pilot | :final

  @type t :: %__MODULE__{
          role: role(),
          family_id: String.t(),
          comparisons: [ComparisonEvidence.t()]
        }

  defstruct [:role, :family_id, :comparisons]
end
