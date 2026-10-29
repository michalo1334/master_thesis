defmodule NetworkDefense.Evaluation2.Study.PilotResult do
  @moduledoc """
  Complete Pilot report of one execution.

  The report holds the compact outcome, the fixed Pilot method and selection
  rule, and every declared candidate with its per comparison assessment. The
  candidate order follows the immutable definition.

  Candidate aggregates are derived operations on
  `NetworkDefense.Evaluation2.Study.PilotResult.Candidate`, so an insufficient
  outcome stays explainable from its comparison details.
  """

  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.PilotResult.Candidate

  @typedoc "Precision method of the Pilot phase."
  @type method :: :precision_pilot_v1

  @typedoc "Runtime rule that ranks passing candidates."
  @type selection_rule :: :lowest_predicted_runtime

  @type t :: %__MODULE__{
          method: method(),
          selection_rule: selection_rule(),
          outcome: PilotOutcome.t(),
          candidates: [Candidate.t()]
        }

  defstruct [:method, :selection_rule, :outcome, :candidates]
end
