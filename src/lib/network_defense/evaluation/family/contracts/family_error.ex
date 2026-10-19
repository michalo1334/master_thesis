defmodule NetworkDefense.Evaluation.Family.Contracts.FamilyError do
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

  def invalid_correction(message \\ "The correction request or response is invalid.")
      when is_binary(message),
      do: new("invalid_response_contract", "invalid_correction", [], message)

  def invalid_correction_issues(issues) when is_list(issues) and issues != [],
    do: %__MODULE__{code: "invalid_response_contract", issues: issues}

  def unavailable,
    do:
      new("compute_unavailable", "compute_unavailable", [], "The compute service is unavailable.")

  def workflow_failed(message \\ "The family workflow failed safely."),
    do: new("workflow_failed", "workflow_failed", [], message)

  def request_too_large(limit_bytes),
    do:
      new(
        "request_too_large",
        "request_too_large",
        [],
        "The request exceeds the byte limit.",
        %{"limit_bytes" => limit_bytes}
      )

  def invalid_json_value(path),
    do:
      new(
        "validation_failed",
        "invalid_type",
        path,
        "The request contains a value that is not valid JSON."
      )

  def validation_failed(issues) when is_list(issues) and issues != [],
    do: %__MODULE__{code: "validation_failed", issues: issues}

  def parse_envelope(value) do
    alias NetworkDefense.Evaluation.Family.SchemaValidator

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
