defmodule NetworkDefense.Evaluation.ErrorReport do
  @moduledoc false

  # Shared diagnostic lines for console output.
  #
  # It reads only bounded contract fields. It never prints stack traces,
  # response bodies, or submitted values.

  def lines(%{issues: issues}) when issues != [] do
    Enum.map(issues, fn issue ->
      "  #{format_path(issue["path"])}: #{issue["code"]}"
    end)
  end

  def lines(%{schema_errors: diagnostics}) do
    Enum.map(diagnostics, fn diagnostic ->
      "  #{format_diagnostic_path(diagnostic["path"])}: #{diagnostic["message"]}"
    end)
  end

  defp format_diagnostic_path(path) when is_binary(path), do: path
  defp format_diagnostic_path(path) when is_list(path), do: format_path(path)
  defp format_diagnostic_path(_path), do: "request"

  defp format_path([]), do: "request"

  defp format_path(path) do
    Enum.reduce(path, "", fn
      item, "" when is_binary(item) -> item
      item, result when is_binary(item) -> result <> "." <> item
      item, result when is_integer(item) -> result <> "[#{item}]"
    end)
  end
end
