defmodule NetworkDefense.Evaluation.Comparison.Contracts.ComparisonError do
  @moduledoc false
  use NetworkDefense.Evaluation.ErrorContract,
    schema_validator: NetworkDefense.Evaluation.Comparison.SchemaValidator,
    request_size: :limit_only

  def invalid_response_contract(
        message \\ "The compute service returned an invalid response contract."
      ),
      do: new("invalid_response_contract", "invalid_response_contract", [], message)

  def unavailable,
    do:
      new("compute_unavailable", "compute_unavailable", [], "The compute service is unavailable.")

  def workflow_failed(message \\ "The comparison workflow failed safely."),
    do: new("workflow_failed", "workflow_failed", [], message)
end
