defmodule NetworkDefense.Evaluation.Family.Actions.CompareMember do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Comparison.Actions.Compare
  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest
  alias NetworkDefense.Evaluation.Family.Contracts.Identity
  alias NetworkDefense.Evaluation.Family.Member
  alias NetworkDefense.Evaluation.Family.TaskFailure

  # Family-member adapter.
  #
  # It passes only the member's comparison request to the accepted Stage 2
  # action. Permanent and retryable failures keep their existing meaning.

  @impl true
  def execute(args, context) do
    item = Keyword.fetch!(args, :item)

    case Member.parse_input(item) do
      {:ok, %{identity: identity, request: request}} ->
        statistics = Compare.execute([request: ComparisonRequest.to_params(request)], context)

        %{"identity" => Identity.to_params(identity), "statistics" => statistics}

      {:error, error} ->
        TaskFailure.raise_permanent(error)
    end
  end
end
