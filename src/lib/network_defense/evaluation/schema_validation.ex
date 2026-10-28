defmodule NetworkDefense.Evaluation.SchemaValidation do
  @moduledoc false

  alias Ecto.Changeset
  alias ExJsonSchema.Schema
  alias ExJsonSchema.Validator
  alias NetworkDefense.Evaluation.SchemaDiagnostics

  def resolve_contents(contents), do: contents |> Jason.decode!() |> resolve_document()

  def resolve_document(document), do: Schema.resolve(document)

  def resolve_payload(document) do
    Schema.resolve(%{
      "$ref" => "#/definitions/payload",
      "definitions" => Map.fetch!(document, "definitions")
    })
  end

  # Resolve the owner's kind inside this boundary. Unknown kinds and failures
  # during validation or diagnostic conversion retain the owner's safe error.
  def validate(value, schema, schema_failure, safe_error) do
    case Validator.validate(schema.(), value, error_formatter: false) do
      :ok -> :ok
      {:error, errors} when is_list(errors) -> {:error, schema_error(errors, schema_failure)}
      {:error, _reason} -> {:error, safe_error.()}
    end
  rescue
    _exception -> {:error, safe_error.()}
  end

  def matches_schema(%Changeset{} = changeset, raw, kind, validate, option_key) do
    case validate.(kind, raw) do
      :ok ->
        changeset

      {:error, error} ->
        Changeset.add_error(changeset, :base, "schema validation failed", [{option_key, error}])
    end
  end

  def error_from_changeset(%Changeset{errors: errors}, fallback, option_key) do
    Enum.find_value(errors, fallback, fn
      {_field, {_message, options}} -> options[option_key]
      _error -> nil
    end)
  end

  def generic_schema_error(message, schema_failure) do
    schema_failure.([%{"message" => message, "path" => "#", "causes" => []}])
  end

  defp schema_error(errors, schema_failure) do
    case SchemaDiagnostics.build(errors) do
      [] -> generic_schema_error("Contract validation failed safely.", schema_failure)
      diagnostics -> schema_failure.(diagnostics)
    end
  end
end
