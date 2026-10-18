defmodule NetworkDefense.Evaluations do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest
  alias NetworkDefense.Evaluation.Comparison.{Wire, Workflow}

  def submit_comparison(attrs) do
    with {:ok, request} <- ComparisonRequest.parse(attrs) do
      request
      |> Wire.request()
      |> Workflow.submit()
    end
  end

  def await_comparison(run_id, timeout_ms), do: Workflow.await(run_id, timeout_ms)
  def get_comparison_result(run_id), do: Workflow.result(run_id)
end
