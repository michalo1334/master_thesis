defmodule NetworkDefense.Evaluation.Study.Contracts.StudyError do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  # Bounded error envelope for the study definition boundary.
  #
  # The shape is the shared evaluation envelope: one code plus a non-empty list
  # of bounded issues. No constructor accepts a parser diagnostic or a submitted
  # value, so no message or detail carries document content. A path names caller
  # keys or list indexes only, and the YAML boundary validates every path
  # component before it adds one.

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

  def schema_failure(diagnostics) when is_list(diagnostics),
    do: %__MODULE__{code: "validation_failed", schema_errors: diagnostics}

  def validation_failed(issues) when is_list(issues) and issues != [],
    do: %__MODULE__{code: "validation_failed", issues: issues}

  def invalid_yaml(path, message) when is_binary(message),
    do: new("validation_failed", "invalid_yaml", path, message)

  def invalid_json_value(path),
    do:
      new(
        "validation_failed",
        "invalid_json_value",
        path,
        "The study definition contains a value that is not valid JSON."
      )

  def structure_limit(path, limit, actual),
    do:
      new(
        "validation_failed",
        "invalid_json_value",
        path,
        "The study definition exceeds a traversal limit.",
        %{"limit" => limit, "actual" => actual}
      )

  def unrepresentable_number(path),
    do:
      new(
        "validation_failed",
        "unrepresentable_number",
        path,
        "The study definition holds a number that cannot be represented as a float."
      )

  def too_large(limit_bytes, message) when is_binary(message),
    do:
      new("request_too_large", "request_too_large", [], message, %{"limit_bytes" => limit_bytes})

  def depth_exceeded(path, limit, actual),
    do:
      new(
        "validation_failed",
        "invalid_yaml",
        path,
        "The YAML document nests deeper than the depth limit.",
        %{"limit" => limit, "actual" => actual}
      )

  def entry_limit_exceeded(path, limit, actual),
    do:
      new(
        "validation_failed",
        "invalid_yaml",
        path,
        "The YAML document holds more entries than the collection limit.",
        %{"limit" => limit, "actual" => actual}
      )

  def new(code, issue_code, path, message, details \\ %{}) do
    %__MODULE__{
      code: code,
      issues: [
        %{"code" => issue_code, "path" => path, "message" => message, "details" => details}
      ]
    }
  end
end
