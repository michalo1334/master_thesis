defmodule NetworkDefense.Evaluation.Family.ResultFormatter do
  @moduledoc false

  alias NetworkDefense.Evaluation.{ErrorReport, Format}

  alias NetworkDefense.Evaluation.Family.Contracts.{FamilyError, FamilyResult, ResultComparison}

  # Console output for one persisted family result.
  #
  # The output always names the synthetic prototype role. It never presents
  # the result as Pilot or Final evidence.

  def success(run_id, %FamilyResult{} = result) do
    [
      "Run: #{run_id}",
      "Status: succeeded",
      "Family: #{result.family_id}",
      "Evidence: #{result.evidence_role} (not Pilot or Final)",
      "Method: #{result.method}",
      "Alpha: #{Format.number(result.alpha)}",
      "Family size: #{result.family_size}",
      "",
      comparisons(result.comparisons),
      "",
      "Intervals are per-comparison and are not simultaneous confidence intervals.",
      "Stored task: correct_family"
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  def failure(run_id, task_name, %FamilyError{} = error) do
    (["Run: #{run_id}", "Status: failed", "Task: #{task_name}", "Error: #{error.code}"] ++
       ErrorReport.lines(error) ++ ["Stored result: none"])
    |> Enum.join("\n")
  end

  def public_rejection(%FamilyError{} = error) do
    (["Run: not created", "Error: #{error.code}"] ++
       ErrorReport.lines(error) ++ ["Stored result: none"])
    |> Enum.join("\n")
  end

  defp comparisons(comparisons) do
    comparisons
    |> Enum.with_index(1)
    |> Enum.map(fn {comparison, position} -> comparison_lines(comparison, position) end)
  end

  defp comparison_lines(%ResultComparison{} = comparison, position) do
    identity = comparison.identity
    statistics = comparison.statistics
    adjustment = comparison.adjustment

    [
      "[#{position}] #{identity.tier} / budget #{identity.budget} / " <>
        "#{identity.alternative} vs #{identity.reference} / #{identity.outcome}",
      "    Difference: #{Format.number(statistics.estimate["value"])} " <>
        "(alternative minus CVSS; lower favors alternative)",
      "    #{Format.percent(statistics.interval["confidence_level"])} CI: " <>
        "[#{Format.number(statistics.interval["lower"])}, " <>
        "#{Format.number(statistics.interval["upper"])}]",
      "    Raw p: #{Format.number(statistics.test["raw_p_value"])}",
      "    Adjusted p: #{Format.number(adjustment.adjusted_p_value)}",
      "    Decision: #{decision(adjustment.reject_null)}",
      ""
    ]
  end

  defp decision(true), do: "reject the null"
  defp decision(false), do: "do not reject the null"
end
