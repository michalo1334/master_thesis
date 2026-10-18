defmodule NetworkDefense.Evaluation.Comparison.SchemaValidator do
  @moduledoc false

  alias Ecto.Changeset
  alias ExJsonSchema.Schema
  alias ExJsonSchema.Validator
  alias ExJsonSchema.Validator.Error
  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonError

  @schema_dir Application.app_dir(:network_defense, "priv/evaluation/contracts/v1/schemas")
  @request_path Path.join(@schema_dir, "request.schema.json")
  @statistics_path Path.join(@schema_dir, "statistics.schema.json")
  @error_path Path.join(@schema_dir, "error.schema.json")
  @external_resource @request_path
  @external_resource @statistics_path
  @external_resource @error_path
  @max_diagnostics 50
  @max_text_bytes 256

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
    {diagnostics, _remaining} = build_diagnostics(errors, @max_diagnostics)

    case diagnostics do
      [] -> generic_schema_error("Contract validation failed safely.")
      _diagnostics -> ComparisonError.schema_failure(diagnostics)
    end
  end

  defp build_diagnostics(_errors, 0), do: {[], 0}
  defp build_diagnostics([], remaining), do: {[], remaining}

  defp build_diagnostics([%Error{} = error | rest], remaining) do
    {diagnostic, remaining} = build_diagnostic(error, remaining)
    {tail, remaining} = build_diagnostics(rest, remaining)
    {[diagnostic | tail], remaining}
  end

  defp build_diagnostics([_unknown | rest], remaining),
    do: build_diagnostics(rest, remaining)

  defp build_diagnostic(%Error{error: reason, path: path}, remaining) do
    {causes, remaining} = build_diagnostics(nested_errors(reason), remaining - 1)

    diagnostic = %{
      "message" => reason |> format_reason() |> bound_utf8(),
      "path" => path |> normalize_diagnostic_path() |> bound_utf8(),
      "causes" => causes
    }

    {diagnostic, remaining}
  end

  defp nested_errors(%Error.AllOf{invalid: invalid}), do: invalid_errors(invalid)
  defp nested_errors(%Error.AnyOf{invalid: invalid}), do: invalid_errors(invalid)
  defp nested_errors(%Error.OneOf{invalid: invalid}), do: invalid_errors(invalid)
  defp nested_errors(%Error.Contains{invalid: invalid}), do: invalid_errors(invalid)
  defp nested_errors(%Error.IfThenElse{errors: errors}), do: errors

  defp nested_errors(%Error.PropertyNames{invalid: invalid}) do
    invalid |> Map.values() |> List.flatten()
  end

  defp nested_errors(_reason), do: []

  defp invalid_errors(invalid) do
    Enum.flat_map(invalid, fn
      %Error.InvalidAtIndex{errors: errors} -> errors
      _invalid -> []
    end)
  end

  defp format_reason(reason) do
    to_string(reason)
  rescue
    _exception -> "Schema validation failed."
  end

  defp normalize_diagnostic_path(path) when is_binary(path) and path != "", do: path
  defp normalize_diagnostic_path(_path), do: "#"

  defp bound_utf8(value) do
    value
    |> :unicode.characters_to_binary()
    |> truncate_utf8(@max_text_bytes)
  rescue
    _exception -> "Schema validation failed."
  end

  defp truncate_utf8(value, limit) when byte_size(value) <= limit, do: value

  defp truncate_utf8(value, limit) do
    candidate = binary_part(value, 0, limit)
    trim_invalid_suffix(candidate)
  end

  defp trim_invalid_suffix(value) do
    case :unicode.characters_to_binary(value) do
      converted when is_binary(converted) -> converted
      {:error, valid, _rest} -> valid
      {:incomplete, valid, _rest} -> valid
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
