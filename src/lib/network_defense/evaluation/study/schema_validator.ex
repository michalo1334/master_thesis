defmodule NetworkDefense.Evaluation.Study.SchemaValidator do
  @moduledoc false

  alias Ecto.Changeset
  alias ExJsonSchema.Schema
  alias ExJsonSchema.Validator
  alias NetworkDefense.Evaluation.SchemaDiagnostics
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  # Strict shape gate for the study definition.
  #
  # The document is checked before any cast, so a raw value such as the string
  # "4" or the float 5.0 never becomes an integer and an unknown field never
  # reaches the typed struct. Diagnostics carry a message, a path, and nested
  # causes only, never a submitted value.

  @schema_dir Application.app_dir(:network_defense, "priv/evaluation/study/v1/schemas")
  @definition_path Path.join(@schema_dir, "definition.schema.json")
  @external_resource @definition_path

  @document @definition_path |> File.read!() |> Jason.decode!()
  @definition_schema Schema.resolve(@document)

  @type kind :: :definition

  @doc "The raw definition schema document, for alignment checks."
  def document, do: @document

  @spec validate(kind(), term()) :: :ok | {:error, StudyError.t()}
  def validate(:definition, value) do
    case Validator.validate(@definition_schema, value, error_formatter: false) do
      :ok -> :ok
      {:error, errors} when is_list(errors) -> {:error, schema_error(errors)}
      {:error, _reason} -> {:error, safe_error()}
    end
  rescue
    _exception -> {:error, safe_error()}
  end

  def matches_schema(%Changeset{} = changeset, raw, kind) do
    case validate(kind, raw) do
      :ok ->
        changeset

      {:error, error} ->
        Changeset.add_error(changeset, :base, "schema validation failed", study_error: error)
    end
  end

  def error_from_changeset(%Changeset{errors: errors}, fallback) do
    Enum.find_value(errors, fallback, fn
      {_field, {_message, options}} -> options[:study_error]
      _error -> nil
    end)
  end

  defp schema_error(errors) do
    case SchemaDiagnostics.build(errors) do
      [] -> generic_schema_error("Study definition validation failed safely.")
      diagnostics -> StudyError.schema_failure(diagnostics)
    end
  end

  defp safe_error, do: generic_schema_error("Study definition validation failed safely.")

  defp generic_schema_error(message) do
    StudyError.schema_failure([
      %{"message" => message, "path" => "#", "causes" => []}
    ])
  end
end
