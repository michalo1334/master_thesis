defmodule NetworkDefense.Evaluation.SchemaDiagnostics do
  @moduledoc false

  # Converts raw JSON Schema validator errors into bounded diagnostics.
  #
  # The diagnostics never contain submitted values. They carry a message, a
  # path, and nested causes only.

  alias ExJsonSchema.Validator.Error

  @max_diagnostics 50
  @max_text_bytes 256

  @spec build([struct()], pos_integer()) :: [map()]
  def build(errors, limit \\ @max_diagnostics) do
    {diagnostics, _remaining} = build_diagnostics(errors, limit)
    diagnostics
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
      "path" => path |> normalize_path() |> bound_utf8(),
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

  defp normalize_path(path) when is_binary(path) and path != "", do: path
  defp normalize_path(_path), do: "#"

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
end
