defmodule NetworkDefense.Evaluation.Pilot.Contracts.PilotError do
  @moduledoc false
  use NetworkDefense.Evaluation.ErrorContract,
    schema_validator: NetworkDefense.Evaluation.Pilot.SchemaValidator,
    request_size: :with_actual,
    identifier_errors: true

  def invalid_response_contract(
        message \\ "The compute service returned an invalid candidate response."
      ),
      do: new("invalid_response_contract", "invalid_response_contract", [], message)

  def invalid_result(message \\ "The stored pilot result is invalid."),
    do: new("invalid_response_contract", "invalid_candidate_result", [], message)

  def incomplete_pilot(message \\ "The persisted pilot is not complete.")
      when is_binary(message),
      do: new("validation_failed", "incomplete_pilot", [], message)

  def changed_candidate_result(message \\ "A persisted candidate result changed.")
      when is_binary(message),
      do: new("validation_failed", "changed_candidate_result", [], message)

  def duplicate_candidate_result(message \\ "A candidate result appears more than once.")
      when is_binary(message),
      do: new("validation_failed", "duplicate_candidate_result", [], message)

  def unexpected_candidate_result(message \\ "A candidate result was not declared.")
      when is_binary(message),
      do: new("validation_failed", "unexpected_candidate_result", [], message)

  def configuration_invalid(message) when is_binary(message),
    do: new("workflow_failed", "configuration_invalid", [], message)

  def snapshot_not_found(message \\ "The evidence snapshot does not exist."),
    do: new("validation_failed", "snapshot_not_found", [], message)

  def snapshot_phase_mismatch(message \\ "The evidence snapshot is not a Pilot snapshot."),
    do: new("validation_failed", "snapshot_phase_mismatch", [], message)

  def changed_snapshot(message \\ "The evidence snapshot does not match the pilot request."),
    do: new("validation_failed", "changed_snapshot", [], message)

  def unavailable,
    do:
      new("compute_unavailable", "compute_unavailable", [], "The compute service is unavailable.")

  def workflow_failed(message \\ "The pilot workflow failed safely."),
    do: new("workflow_failed", "workflow_failed", [], message)

  def validation_failed(issues) when is_list(issues) and issues != [],
    do: %__MODULE__{code: "validation_failed", issues: issues}
end
