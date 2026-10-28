defmodule NetworkDefense.Evaluation.SnapshotDimensions do
  @moduledoc false

  import NetworkDefense.Evaluation.ContractSupport

  @max_issues 50

  def validate(comparisons, comparison_limit, comparison_issues) do
    count = length(comparisons)

    if count <= comparison_limit do
      matrix_dimensions(comparisons, comparison_issues)
    else
      {:comparison_limit,
       limit_issue(
         ["payload", "comparisons"],
         "The snapshot comparison count exceeds the configured limit.",
         comparison_limit,
         count
       )}
    end
  end

  def comparison_issues(evidence, index, plans_per_side, attack_columns) do
    row_issues(
      length(evidence.alternative.plans),
      ["payload", "comparisons", index, "evidence", "alternative", "plans"],
      plans_per_side
    ) ++
      row_issues(
        length(evidence.reference.plans),
        ["payload", "comparisons", index, "evidence", "reference", "plans"],
        plans_per_side
      ) ++ attack_issues(length(evidence.attack_seeds), index, attack_columns)
  end

  defp matrix_dimensions(comparisons, comparison_issues) do
    issues =
      comparisons
      |> Enum.with_index()
      |> Enum.flat_map(fn {comparison, index} -> comparison_issues.(comparison, index) end)
      |> Enum.take(@max_issues)

    case issues do
      [] -> :ok
      _issues -> {:matrix_limits, issues}
    end
  end

  defp row_issues(count, path, limit) do
    if count <= limit do
      []
    else
      [
        limit_issue(
          path,
          "The comparison side has more plan rows than the configured limit.",
          limit,
          count
        )
      ]
    end
  end

  defp attack_issues(count, index, limit) do
    if count <= limit do
      []
    else
      [
        limit_issue(
          ["payload", "comparisons", index, "evidence", "attack_seeds"],
          "The comparison has more attack columns than the configured limit.",
          limit,
          count
        )
      ]
    end
  end

  defp limit_issue(path, message, limit, actual) do
    issue("invalid_analysis_setting", path, message, %{"limit" => limit, "actual" => actual})
  end
end
