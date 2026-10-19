defmodule NetworkDefense.Evaluation.Comparison.SchemaValidator do
  @moduledoc false

  alias Ecto.Changeset
  alias ExJsonSchema.Schema
  alias ExJsonSchema.Validator
  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonError
  alias NetworkDefense.Evaluation.SchemaDiagnostics

  @schema_dir Application.app_dir(:network_defense, "priv/evaluation/contracts/v1/schemas")
  @request_path Path.join(@schema_dir, "request.schema.json")
  @statistics_path Path.join(@schema_dir, "statistics.schema.json")
  @error_path Path.join(@schema_dir, "error.schema.json")
  @external_resource @request_path
  @external_resource @statistics_path
  @external_resource @error_path
  @request_schema @request_path |> File.read!() |> Jason.decode!() |> Schema.resolve()
  @statistics_schema @statistics_path |> File.read!() |> Jason.decode!() |> Schema.resolve()
  @error_schema @error_path |> File.read!() |> Jason.decode!() |> Schema.resolve()

  @spec validate(:request | :statistics | :error, term()) ::
          :ok | {:error, ComparisonError.t()}
  def validate(kind, value) do
    case Validator.validate(schema(kind), value, error_formatter: false) do
      :ok -> :ok
      {:error, errors} when is_list(errors) -> {:error, schema_error(errors)}
      {:error, _reason} -> {:error, safe_error(kind)}
    end
  rescue
    _exception -> {:error, safe_error(kind)}
  end

  def matches_schema(%Changeset{} = changeset, raw, kind) do
    case validate(kind, raw) do
      :ok ->
        changeset

      {:error, error} ->
        Changeset.add_error(changeset, :base, "schema validation failed", comparison_error: error)
    end
  end

  def error_from_changeset(%Changeset{errors: errors}, fallback) do
    Enum.find_value(errors, fallback, fn
      {_field, {_message, options}} -> options[:comparison_error]
      _error -> nil
    end)
  end

  defp schema(:request), do: @request_schema
  defp schema(:statistics), do: @statistics_schema
  defp schema(:error), do: @error_schema

  defp schema_error(errors) do
    case SchemaDiagnostics.build(errors) do
      [] -> generic_schema_error("Contract validation failed safely.")
      diagnostics -> ComparisonError.schema_failure(diagnostics)
    end
  end

  defp generic_schema_error(message) do
    ComparisonError.schema_failure([
      %{"message" => message, "path" => "#", "causes" => []}
    ])
  end

  defp safe_error(:request), do: generic_schema_error("Request validation failed safely.")
  defp safe_error(_kind), do: ComparisonError.invalid_response_contract()
end
