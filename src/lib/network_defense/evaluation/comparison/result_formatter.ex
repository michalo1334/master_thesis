defmodule NetworkDefense.Evaluation.Comparison.ResultFormatter do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonError, ComparisonStatistics}
  alias NetworkDefense.Evaluation.{ErrorReport, Format}

  def success(run_id, %ComparisonStatistics{} = statistics) do
    [
      "Run: #{run_id}",
      "Status: succeeded",
      "",
      "Difference: #{Format.number(statistics.estimate["value"])} " <>
        "(alternative minus CVSS; lower favors alternative)",
      "#{Format.percent(statistics.interval["confidence_level"])} CI: " <>
        "[#{Format.number(statistics.interval["lower"])}, " <>
        "#{Format.number(statistics.interval["upper"])}]",
      "Raw p: #{Format.number(statistics.test["raw_p_value"])}",
      "Assessment: #{statistics.assessment["status"]}",
      "",
      "Stored task: compare"
    ]
    |> Enum.join("\n")
  end

  def failure(run_id, task_name, %ComparisonError{} = error) do
    (["Run: #{run_id}", "Status: failed", "Task: #{task_name}", "Error: #{error.code}"] ++
       ErrorReport.lines(error) ++ ["Stored result: none"])
    |> Enum.join("\n")
  end

  def public_rejection(%ComparisonError{} = error) do
    (["Run: not created", "Error: #{error.code}"] ++
       ErrorReport.lines(error) ++ ["Stored result: none"])
    |> Enum.join("\n")
  end
end
