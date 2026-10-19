defmodule NetworkDefense.Evaluation.Family.SchemaValidator do
  @moduledoc false

  alias Ecto.Changeset
  alias ExJsonSchema.Schema
  alias ExJsonSchema.Validator
  alias NetworkDefense.Evaluation.Family.Contracts.FamilyError
  alias NetworkDefense.Evaluation.SchemaDiagnostics

  @schema_dir Application.app_dir(:network_defense, "priv/evaluation/family/v1/schemas")
  @request_path Path.join(@schema_dir, "request.schema.json")
  @holm_request_path Path.join(@schema_dir, "holm_request.schema.json")
  @holm_response_path Path.join(@schema_dir, "holm_response.schema.json")
  @result_path Path.join(@schema_dir, "result.schema.json")
  @error_path Path.join(@schema_dir, "error.schema.json")
  @external_resource @request_path
  @external_resource @holm_request_path
  @external_resource @holm_response_path
  @external_resource @result_path
  @external_resource @error_path

  @request_schema @request_path |> File.read!() |> Jason.decode!() |> Schema.resolve()
  @holm_request_schema @holm_request_path |> File.read!() |> Jason.decode!() |> Schema.resolve()
  @holm_response_schema @holm_response_path |> File.read!() |> Jason.decode!() |> Schema.resolve()
  @result_schema @result_path |> File.read!() |> Jason.decode!() |> Schema.resolve()
  @error_schema @error_path |> File.read!() |> Jason.decode!() |> Schema.resolve()

  @type kind :: :request | :holm_request | :holm_response | :result | :error

  @spec validate(kind(), term()) :: :ok | {:error, FamilyError.t()}
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
        Changeset.add_error(changeset, :base, "schema validation failed", family_error: error)
    end
  end

  def error_from_changeset(%Changeset{errors: errors}, fallback) do
    Enum.find_value(errors, fallback, fn
      {_field, {_message, options}} -> options[:family_error]
      _error -> nil
    end)
  end

  defp schema(:request), do: @request_schema
  defp schema(:holm_request), do: @holm_request_schema
  defp schema(:holm_response), do: @holm_response_schema
  defp schema(:result), do: @result_schema
  defp schema(:error), do: @error_schema

  defp schema_error(errors) do
    case SchemaDiagnostics.build(errors) do
      [] -> generic_schema_error("Contract validation failed safely.")
      diagnostics -> FamilyError.schema_failure(diagnostics)
    end
  end

  defp generic_schema_error(message) do
    FamilyError.schema_failure([
      %{"message" => message, "path" => "#", "causes" => []}
    ])
  end

  defp safe_error(:request), do: generic_schema_error("Family request validation failed safely.")
  defp safe_error(_kind), do: FamilyError.invalid_response_contract()
end
