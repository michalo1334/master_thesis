defmodule NetworkDefense.Evaluation.Family.Contracts.FamilyError do
  @moduledoc false
  use NetworkDefense.Evaluation.ErrorContract,
    schema_validator: NetworkDefense.Evaluation.Family.SchemaValidator,
    request_size: :limit_only,
    correction_errors: true

  def invalid_response_contract(
        message \\ "The compute service returned an invalid correction response."
      ),
      do: new("invalid_response_contract", "invalid_response_contract", [], message)

  def invalid_result(message \\ "The stored family result is invalid."),
    do: new("invalid_response_contract", "family_result_invalid", [], message)

  def incomplete_family(message \\ "The persisted family is not complete.")
      when is_binary(message),
      do: new("validation_failed", "incomplete_family", [], message)

  def changed_member(message \\ "A persisted family member changed.") when is_binary(message),
    do: new("validation_failed", "changed_family_member", [], message)

  def unavailable,
    do:
      new("compute_unavailable", "compute_unavailable", [], "The compute service is unavailable.")

  def workflow_failed(message \\ "The family workflow failed safely."),
    do: new("workflow_failed", "workflow_failed", [], message)

  def validation_failed(issues) when is_list(issues) and issues != [],
    do: %__MODULE__{code: "validation_failed", issues: issues}
end
