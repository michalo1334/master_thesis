defmodule NetworkDefense.Evaluation2.Study.PilotOutcome do
  @moduledoc """
  Compact Pilot decision of one study.

  A recommendation names the declared candidate and the two sample counts that
  Final collection must reproduce. An insufficient outcome holds its tag only.
  The reason is implied by the methodology: no declared candidate passed every
  comparison.

  The same value is the internal compact outcome of one execution and the
  supported public value.
  """

  use Spectral

  @typedoc """
  Identifier of one declared Pilot candidate.

  The identifier names a sample-size choice of the Pilot candidate grid.
  """
  @type candidate_id :: String.t()

  @typedoc "Tag of one Pilot decision."
  @type outcome :: :recommended | :insufficient

  @type t :: recommended() | insufficient()

  @typedoc "A declared candidate passed every comparison."
  @type recommended :: %__MODULE__{
          outcome: :recommended,
          candidate_id: candidate_id(),
          plan_count_per_side: pos_integer(),
          attacks_per_plan: pos_integer()
        }

  @typedoc "No declared candidate passed every comparison."
  @type insufficient :: %__MODULE__{
          outcome: :insufficient,
          candidate_id: nil,
          plan_count_per_side: nil,
          attacks_per_plan: nil
        }

  defstruct [:outcome, :candidate_id, :plan_count_per_side, :attacks_per_plan]
end
