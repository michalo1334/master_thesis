defmodule NetworkDefense.Evaluation2.Study.Final.Analysis do
  @moduledoc false

  # One service owns the complete Final analysis, including family correction.
  # Gust actions provide scheduling rather than separate scientific boundaries.
  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Final.AnalysisContract
  alias NetworkDefense.Evaluation2.Study.Final.ComparisonJob
  alias NetworkDefense.Evaluation2.Study.Result.Comparison

  @spec prepare(Ecto.UUID.t()) :: {:ok, [ComparisonJob.t()]} | {:error, Error.t()}
  def prepare(_snapshot_id), do: {:error, Placeholder.error(:prepare)}

  @spec evaluate(Ecto.UUID.t(), ComparisonJob.t()) ::
          {:ok, Comparison.Statistics.t()} | {:error, Error.t()}
  def evaluate(_snapshot_id, _job), do: {:error, Placeholder.error(:evaluate)}

  @spec correct(Ecto.UUID.t(), [Comparison.Statistics.t()]) ::
          {:ok, AnalysisContract.Output.t()} | {:error, Error.t()}
  def correct(_snapshot_id, _statistics), do: {:error, Placeholder.error(:correct)}
end
