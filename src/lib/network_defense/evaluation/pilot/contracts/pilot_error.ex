defmodule NetworkDefense.Evaluation.Pilot.Contracts.PilotError do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.ErrorEnvelope

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
      new(
        "validation_failed",
        "invalid_identifier",
        path,
        "The value must be a canonical UUID."
      )

  def validation_failed(issues) when is_list(issues) and issues != [],
    do: %__MODULE__{code: "validation_failed", issues: issues}

  def parse_envelope(value) do
    alias NetworkDefense.Evaluation.Pilot.SchemaValidator

    with {:ok, attrs} <- ErrorEnvelope.parse(value, &SchemaValidator.validate(:error, &1)) do
      {:ok, struct!(__MODULE__, attrs)}
    end
  end

  def materialize_envelope(value) do
    with {:ok, attrs} <- ErrorEnvelope.materialize(value), do: {:ok, struct!(__MODULE__, attrs)}
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
