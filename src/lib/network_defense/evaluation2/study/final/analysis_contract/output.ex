defmodule NetworkDefense.Evaluation2.Study.Final.AnalysisContract.Output do
  @moduledoc false

  # Terminal output of one Final analysis Gust run.
  #
  # The terminal output holds the corrected comparison family of the declared
  # family, and the lifecycle stores it once as the result record.

  alias NetworkDefense.Evaluation2.Study.Final.CorrectedFamily

  @type t :: %__MODULE__{family_result: CorrectedFamily.t()}

  defstruct [:family_result]
end
