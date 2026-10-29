defmodule NetworkDefense.Evaluation2.Study.Final.Timing do
  @moduledoc false

  # One clock owner of Final collection timing.
  #
  # Every timing boundary of a tier run is taken by the coordinator that awaits
  # the run, so queue time and Gust retry delay stay inside the measured interval.
  #
  # The summary keeps raw measurements without warm-up. Public
  # Study.Result.Timing owns median and range queries.

  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Study.Final.TierRun
  alias NetworkDefense.Evaluation2.Study.Result.Timing

  @spec summarize([TierRun.t()]) :: Timing.t()
  def summarize(_tier_runs), do: raise(NotImplementedError, function: :summarize)
end
