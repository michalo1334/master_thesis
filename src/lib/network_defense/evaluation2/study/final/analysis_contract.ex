defmodule NetworkDefense.Evaluation2.Study.Final.AnalysisContract do
  @moduledoc false

  # Input and output contract of one Final analysis Gust run.
  #
  # The root input names the phase-run record and the accepted Final snapshot.
  # The terminal output holds the corrected comparison family of the declared
  # family.

  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Study.Final.AnalysisContract.{Input, Output}

  @spec to_params(Input.t()) :: map()
  def to_params(_input), do: raise(NotImplementedError, function: :to_params)

  @spec decode_output!(map()) :: Output.t()
  def decode_output!(_params), do: raise(NotImplementedError, function: :decode_output!)
end
