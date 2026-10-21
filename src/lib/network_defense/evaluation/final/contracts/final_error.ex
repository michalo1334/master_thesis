defmodule NetworkDefense.Evaluation.Final.Contracts.FinalError do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.ErrorEnvelope

  # Bounded typed error for the Final snapshot, Final request, and Final
  # workflow. The codes follow the accepted Stage 2 and Stage 3 envelopes. Final
  # adds source-binding issue codes, so a caller can tell a Pilot binding
  # failure from an evidence or correlation failure.

  @type t :: %__MODULE__{
          schema_version: integer(),
          code: String.t(),
          issues: [map()],
          schema_errors: [map()]
        }

  embedded_schema do
    field :schema_version, :integer, default: 1
    field :code, :string
    field :issues, {:array, :map}, default: []
    field :schema_errors, {:array, :map}, default: []
  end

  def changeset(error, attrs),
    do: cast(error, attrs, [:schema_version, :code, :issues, :schema_errors])

  def schema_failure(diagnostics),
    do: %__MODULE__{code: "validation_failed", schema_errors: diagnostics}

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

  def invalid_correction(message \\ "The correction request or response is invalid.")
      when is_binary(message),
      do: new("invalid_response_contract", "invalid_correction", [], message)

  def invalid_correction_issues(issues) when is_list(issues) and issues != [],
    do: %__MODULE__{code: "invalid_response_contract", issues: issues}

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

  def request_too_large(limit_bytes, actual_bytes \\ nil) do
    details =
      if is_integer(actual_bytes) do
        %{"limit_bytes" => limit_bytes, "actual_bytes" => actual_bytes}
      else
        %{"limit_bytes" => limit_bytes}
      end

    new(
      "request_too_large",
      "request_too_large",
      [],
      "The request exceeds the byte limit.",
      details
    )
  end

  def invalid_json_value(path),
    do:
      new(
        "validation_failed",
        "invalid_type",
        path,
        "The request contains a value that is not valid JSON."
      )

  def invalid_identifier(path),
    do:
      new("validation_failed", "invalid_identifier", path, "The value must be a canonical UUID.")

  def validation_failed(issues) when is_list(issues) and issues != [],
    do: %__MODULE__{code: "validation_failed", issues: issues}

  def parse_envelope(value) do
    alias NetworkDefense.Evaluation.Final.SchemaValidator

    with {:ok, attrs} <- ErrorEnvelope.parse(value, &SchemaValidator.validate(:error, &1)) do
      {:ok, struct!(__MODULE__, attrs)}
    end
  end

  def materialize_envelope(value) do
    with {:ok, attrs} <- ErrorEnvelope.materialize(value), do: {:ok, struct!(__MODULE__, attrs)}
  end

  @doc "Copy a bounded error from another evaluation contract into a Final error."
  def from_foreign(%{code: code} = error) do
    %__MODULE__{
      code: code,
      issues: Map.get(error, :issues, []),
      schema_errors: Map.get(error, :schema_errors, [])
    }
  end

  def new(code, issue_code, path, message, details \\ %{}) do
    %__MODULE__{
      code: code,
      issues: [
        %{"code" => issue_code, "path" => path, "message" => message, "details" => details}
      ]
    }
  end
end
