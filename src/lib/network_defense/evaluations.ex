defmodule NetworkDefense.Evaluations do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest
  alias NetworkDefense.Evaluation.Comparison.{Wire, Workflow}
  alias NetworkDefense.Evaluation.Family
  alias NetworkDefense.Evaluation.Family.Contracts.FamilyRequest

  def submit_comparison(attrs) do
    with {:ok, request} <- ComparisonRequest.parse(attrs) do
      request
      |> Wire.request()
      |> Workflow.submit()
    end
  end

  def await_comparison(run_id, timeout_ms), do: Workflow.await(run_id, timeout_ms)
  def get_comparison_result(run_id), do: Workflow.result(run_id)

  def submit_family(attrs) do
    with {:ok, request} <- FamilyRequest.parse(attrs) do
      request
      |> Family.Wire.request()
      |> Family.Workflow.submit()
    end
  end

  def await_family(run_id, timeout_ms), do: Family.Workflow.await(run_id, timeout_ms)
  def get_family_result(run_id), do: Family.Workflow.result(run_id)
end
