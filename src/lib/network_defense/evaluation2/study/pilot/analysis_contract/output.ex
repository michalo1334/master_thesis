defmodule NetworkDefense.Evaluation2.Study.Pilot.AnalysisContract.Output do
  @moduledoc false

  # Terminal output of one Pilot analysis Gust run.
  #
  # The lifecycle stores the compact outcome only, so the complete candidate
  # summaries stay in this terminal Gust result.

  alias NetworkDefense.Evaluation2.Study.Pilot.Summary
  alias NetworkDefense.Evaluation2.Study.PilotOutcome

  @type t :: %__MODULE__{
          outcome: PilotOutcome.t(),
          candidates: [Summary.t()]
        }

  defstruct [:outcome, :candidates]
end
