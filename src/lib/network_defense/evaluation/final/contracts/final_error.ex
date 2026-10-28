defmodule NetworkDefense.Evaluation.Final.Contracts.FinalError do
  @moduledoc false
  use NetworkDefense.Evaluation.ErrorContract,
    schema_validator: NetworkDefense.Evaluation.Final.SchemaValidator,
    request_size: :with_actual,
    identifier_errors: true,
    correction_errors: true

  # Bounded typed error for the Final snapshot, Final request, and Final
  # workflow. The codes follow the accepted Stage 2 and Stage 3 envelopes. Final
  # adds source-binding issue codes, so a caller can tell a Pilot binding
  # failure from an evidence or correlation failure.

  def invalid_response_contract(
        message \\ "The compute service returned an invalid correction response."
      ),
      do: new("invalid_response_contract", "invalid_response_contract", [], message)

  def invalid_result(message \\ "The stored Final result is invalid."),
    do: new("invalid_response_contract", "final_result_invalid", [], message)

  def incomplete_family(message \\ "The persisted Final family is not complete.")
      when is_binary(message),
      do: new("validation_failed", "incomplete_family", [], message)

  def changed_member(message \\ "A persisted Final family member changed.")
      when is_binary(message),
      do: new("validation_failed", "changed_family_member", [], message)

  def changed_snapshot(message \\ "The Final snapshot does not match the Final request.")
      when is_binary(message),
      do: new("validation_failed", "changed_snapshot", [], message)

  def snapshot_not_found(message \\ "The Final evidence snapshot does not exist."),
    do: new("validation_failed", "snapshot_not_found", [], message)

  def snapshot_phase_mismatch(message \\ "The evidence snapshot is not a Final snapshot."),
    do: new("validation_failed", "snapshot_phase_mismatch", [], message)

  def pilot_not_recommended(message \\ "The source Pilot is not a recommended Pilot result.")
      when is_binary(message),
      do: new("validation_failed", "pilot_not_recommended", [], message)

  def pilot_not_found(message \\ "The source Pilot result does not exist.")
      when is_binary(message),
      do: new("validation_failed", "pilot_not_found", [], message)

  def pilot_source_invalid(reason, message \\ "The source Pilot result is not readable.")
      when is_binary(reason) and is_binary(message),
      do: new("validation_failed", "pilot_source_invalid", [], message, %{"reason" => reason})

  def count_mismatch(message \\ "The Final counts do not equal the Pilot recommendation.")
      when is_binary(message),
      do: new("validation_failed", "count_mismatch", [], message)

  def changed_pilot_source(message \\ "The Final request does not repeat the Pilot source.")
      when is_binary(message),
      do: new("validation_failed", "changed_pilot_source", [], message)

  def invalid_assertion(message \\ "The caller assertion is not valid.")
      when is_binary(message),
      do: new("validation_failed", "invalid_assertion", [], message)

  def unavailable,
    do:
      new("compute_unavailable", "compute_unavailable", [], "The compute service is unavailable.")

  def configuration_invalid(message) when is_binary(message),
    do: new("workflow_failed", "configuration_invalid", [], message)

  def bootstrap_replicates_exceeded(
        message \\ "The requested bootstrap work exceeds the Final replicate limit."
      )
      when is_binary(message),
      do:
        new(
          "validation_failed",
          "bootstrap_replicates_exceeded",
          ["analysis", "bootstrap_replicates"],
          message
        )

  def work_limit_exceeded(message \\ "The requested bootstrap work exceeds the Final work limit.")
      when is_binary(message),
      do: new("validation_failed", "work_limit_exceeded", [], message)

  def invalid_argument(message) when is_binary(message),
    do: new("validation_failed", "invalid_argument", [], message)

  def workflow_failed(message \\ "The Final workflow failed safely."),
    do: new("workflow_failed", "workflow_failed", [], message)

  def validation_failed(issues) when is_list(issues) and issues != [],
    do: %__MODULE__{code: "validation_failed", issues: issues}

  @doc "Copy a bounded error from another evaluation contract into a Final error."
  def from_foreign(%{code: code} = error) do
    %__MODULE__{
      code: code,
      issues: Map.get(error, :issues, []),
      schema_errors: Map.get(error, :schema_errors, [])
    }
  end
end
