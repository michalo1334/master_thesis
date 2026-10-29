defmodule NetworkDefense.Evaluation2.Study.Final.Timing do
  @moduledoc """
  One clock owner of Final collection timing.

  Every timing boundary of a tier run is taken by the coordinator that awaits the
  run, so queue time and Gust retry delay stay inside the measured interval.
  Summaries keep the declared tier order.
  """

  alias NetworkDefense.Evaluation2.FinalTierRunResult
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Timing.TimingSummary

  @doc """
  Summarize the timing of completed tier runs.

  The result holds one tier entry per declared tier, in declared tier order.
  """
  @spec summarize([FinalTierRunResult.t()]) :: TimingSummary.t()
  def summarize(_tier_results), do: raise(NotImplementedError, function: :summarize)
end
