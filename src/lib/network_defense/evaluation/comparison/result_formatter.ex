defmodule NetworkDefense.Evaluation.Comparison.ResultFormatter do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonError, ComparisonStatistics}

  def success(run_id, %ComparisonStatistics{} = statistics) do
    [
      "Run: #{run_id}",
      "Status: succeeded",
      "",
      "Difference: #{format_number(statistics.estimate["value"])} " <>
        "(alternative minus CVSS; lower favors alternative)",
      "#{format_percent(statistics.interval["confidence_level"])} CI: " <>
        "[#{format_number(statistics.interval["lower"])}, " <>
        "#{format_number(statistics.interval["upper"])}]",
      "Raw p: #{format_number(statistics.test["raw_p_value"])}",
      "Assessment: #{statistics.assessment["status"]}",
      "",
      "Stored task: compare"
    ]
    |> Enum.join("\n")
  end

  def failure(run_id, task_name, %ComparisonError{} = error) do
    (["Run: #{run_id}", "Status: failed", "Task: #{task_name}", "Error: #{error.code}"] ++
       error_lines(error) ++ ["Stored result: none"])
    |> Enum.join("\n")
  end

  def public_rejection(%ComparisonError{} = error) do
    (["Run: not created", "Error: #{error.code}"] ++
       error_lines(error) ++ ["Stored result: none"])
    |> Enum.join("\n")
  end

  defp error_lines(%ComparisonError{issues: issues}) when issues != [] do
    Enum.map(issues, fn issue ->
      "  #{format_path(issue["path"])}: #{issue["code"]}"
    end)
  end

  defp error_lines(%ComparisonError{schema_errors: diagnostics}) do
    Enum.map(diagnostics, fn diagnostic ->
      "  #{format_diagnostic_path(diagnostic["path"])}: #{diagnostic["message"]}"
    end)
  end

  defp format_number(number),
    do: :erlang.float_to_binary(number / 1, decimals: 4) |> trim_zeroes()

  defp format_percent(number), do: "#{round(number * 100)}%"

  defp trim_zeroes(value) do
    value |> String.trim_trailing("0") |> String.trim_trailing(".")
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
