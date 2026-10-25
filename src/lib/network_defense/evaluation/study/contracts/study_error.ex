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

  def graph_revision_not_found(path),
    do:
      new(
        "validation_failed",
        "graph_revision_not_found",
        path,
        "A declared graph revision does not exist."
      )

  def duplicate_revision,
    do:
      new(
        "conflict",
        "study_revision_exists",
        [],
        "The study revision already exists."
      )

  def storage_failed,
    do:
      new(
        "unavailable",
        "storage_failed",
        [],
        "The study revision could not be stored safely."
      )

  def collection_item_storage_failed,
    do:
      new(
        "unavailable",
        "storage_failed",
        [],
        "The study collection item could not be stored safely."
      )

  def invalid_study_phase,
    do:
      new(
        "validation_failed",
        "invalid_study_phase",
        [],
        "The study phase identifier does not name a stored study phase."
      )

  def invalid_collection_position(field) when field in [:replica_position, :item_position],
    do:
      new(
        "validation_failed",
        "invalid_collection_position",
        [Atom.to_string(field)],
        "A collection position is not a non-negative integer."
      )

  def collection_item_not_found,
    do:
      new(
        "validation_failed",
        "collection_item_not_found",
        ["id"],
        "The study collection item does not exist."
      )

  def runtime_record_mismatch(field) when field in [:optimization_run_id, :experiment_id],
    do:
      new(
        "conflict",
        "runtime_record_mismatch",
        [Atom.to_string(field)],
        "The linked runtime record does not match the declared request."
      )

  def runtime_request_invalid(field, reason)
      when field in [:optimization_run_id, :experiment_id] and is_atom(reason),
      do:
        new(
          "validation_failed",
          "runtime_request_invalid",
          [Atom.to_string(field)],
          "The runtime request is not valid for the collection item.",
          %{"reason" => Atom.to_string(reason)}
        )

  def runtime_record_unavailable(field, reason)
      when field in [:optimization_run_id, :experiment_id] and is_atom(reason),
      do:
        new(
          "unavailable",
          "runtime_record_unavailable",
          [Atom.to_string(field)],
          "The runtime record is not available for the collection item.",
          %{"reason" => Atom.to_string(reason)}
        )

  def collection_configuration_invalid,
    do:
      new(
        "unavailable",
        "configuration_invalid",
        [],
        "The study collection controls are missing or invalid."
      )

  def unsupported_collection_phase(phase) when is_atom(phase),
    do:
      new(
        "validation_failed",
        "unsupported_collection_phase",
        ["phase"],
        "Only Pilot collection is supported.",
        %{"phase" => Atom.to_string(phase)}
      )

  def collection_phase_mismatch,
    do:
      new(
        "validation_failed",
        "collection_phase_mismatch",
        ["phase"],
        "The study phase does not belong to the study execution."
      )

  def incomplete_collection_definition(path) when is_list(path),
    do:
      new(
        "validation_failed",
        "incomplete_collection_definition",
        path,
        "The study definition does not supply a required collection declaration."
      )

  def collection_work_exceeds_limit(limit, actual)
      when is_integer(limit) and is_integer(actual),
      do:
        new(
          "validation_failed",
          "collection_work_limit_exceeded",
          ["phase"],
          "The phase work exceeds the configured item limit.",
          %{"limit" => limit, "actual" => actual}
        )

  def collection_work_mismatch(field) when field in [:replica_position, :item_position],
    do:
      new(
        "conflict",
        "collection_work_mismatch",
        [Atom.to_string(field)],
        "The work item does not match the persisted collection item."
      )

  def collection_result_invalid,
    do:
      new(
        "unavailable",
        "incomplete_collection_result",
        [],
        "The collection item did not produce one complete runtime result."
      )

  def runtime_execution_failed(field, reason)
      when field in [:optimization_run_id, :experiment_id],
      do:
        new(
          "unavailable",
          "runtime_execution_failed",
          [Atom.to_string(field)],
          "The reserved runtime record did not complete.",
          %{"reason" => reason_label(reason)}
        )

  defp reason_label(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_label(_reason), do: "unavailable"

  def new(code, issue_code, path, message, details \\ %{}) do
    %__MODULE__{
      code: code,
      issues: [
        %{"code" => issue_code, "path" => path, "message" => message, "details" => details}
      ]
    }
  end
end
