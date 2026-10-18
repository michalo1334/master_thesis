defmodule NetworkDefense.Evaluation.Comparison.Actions.Prepare do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest
  alias NetworkDefense.Evaluation.Comparison.TaskFailure

  @impl true
  def execute(_args, %{run_id: run_id}) do
    request = Gust.Flows.get_run!(run_id).params

    case ComparisonRequest.parse(request) do
      {:ok, _request} -> :ok
      {:error, error} -> TaskFailure.raise_permanent(error)
    end
  end
end
