defmodule NetworkDefense.Evaluation.Comparison.Actions.Compare do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Comparison.{Client, TaskFailure, Wire}
  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest

  @impl true
  def execute(args, _context) do
    with raw_request when is_map(raw_request) <- Keyword.fetch!(args, :request),
         {:ok, request} <- ComparisonRequest.parse(raw_request),
         {:ok, statistics} <- Client.compare(request) do
      Wire.statistics(statistics)
    else
      {:error, :permanent, error} -> TaskFailure.raise_permanent(error)
      {:error, :temporary, error} -> TaskFailure.raise_retryable(error)
      {:error, error} -> TaskFailure.raise_permanent(error)
    end
  end
end
