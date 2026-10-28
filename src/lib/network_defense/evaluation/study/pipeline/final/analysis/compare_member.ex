defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.CompareMember do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Actions.Compare
  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest
  alias NetworkDefense.Evaluation.Family.Contracts.Identity
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO.ComparisonItem
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Member
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Error, as: FinalError

  # One mapped Final comparison.
  #
  # The item carries one declared position and one declared identity, and the
  # comparison request is already rebuilt from the stored Final snapshot and the
  # submitted seed. The step delegates the statistics to the accepted Stage 2
  # action and checks the returned statistics against the same request.
  #
  # The step runs after preparation validated the snapshot metadata, the
  # snapshot byte count, the declared order, the resource caps, and the actual
  # source Pilot binding. A snapshot or Pilot that changed after preparation
  # therefore stops the member with no compute call.

  @spec run(ComparisonItem.t()) :: {:ok, ComparisonItem.t()} | {:error, FinalError.t()}
  def run(%ComparisonItem{} = comparison) do
    with {:ok, _request, _payload} <- ComparisonItem.values(comparison),
         {:ok, comparison_request} <- comparison_request(comparison),
         {:ok, item} <- item(comparison),
         statistics =
           Compare.execute([request: ComparisonRequest.to_params(comparison_request)], %{}),
         {:ok, result} <- parse_result(statistics, item, comparison_request) do
      {:ok, %{comparison | result: result}}
    end
  end

  defp comparison_request(%ComparisonItem{comparison_request: %ComparisonRequest{} = request}),
    do: {:ok, request}

  defp comparison_request(%ComparisonItem{}) do
    {:error, FinalError.incomplete_family("The mapped Final comparison is not prepared.")}
  end

  defp item(%ComparisonItem{item: item}) do
    case Member.parse_item(item) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, %FinalError{} = error} -> {:error, error}
    end
  end

  defp parse_result(statistics, item, %ComparisonRequest{} = comparison_request) do
    case Member.parse_result(
           %{"identity" => Identity.to_params(item.identity), "statistics" => statistics},
           comparison_request
         ) do
      {:ok, result} -> {:ok, result}
      {:error, %FinalError{} = error} -> {:error, error}
    end
  end

  defmodule Gust do
    @moduledoc false

    use NetworkDefense.Evaluation.Study.Pipeline.GustAdapter,
      step: NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.CompareMember,
      failures: NetworkDefense.Evaluation.Study.Pipeline.Final.TaskFailure

    alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonStatistics
    alias NetworkDefense.Evaluation.Family.Contracts.Identity
    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO
    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO.ComparisonItem
    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter

    @impl GustAdapter
    def decode(args, %{run_id: run_id}) do
      with {:ok, io} <- IO.load_from_gust_run(run_id) do
        IO.comparison(io, Keyword.fetch!(args, :item))
      end
    end

    @impl GustAdapter
    def encode(%ComparisonItem{result: result}) when not is_nil(result) do
      %{
        "identity" => Identity.to_params(result.identity),
        "statistics" => ComparisonStatistics.to_params(result.statistics)
      }
    end
  end
end
