defmodule NetworkDefense.Evaluation.Pilot.SnapshotLimits do
  @moduledoc false

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    ComparisonEvidence,
    PilotError,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Pilot.Limits

  # Dimension checks for stored evidence.
  #
  # Creation and every read call this module with the required application
  # limits. The check covers the comparison count and the stored matrix shape:
  # plan rows on each side and attack columns for every comparison. The check
  # never changes or truncates the payload.

  @max_issues 50

  @spec validate(SnapshotPayload.t()) :: :ok | {:error, PilotError.t()}
  def validate(%SnapshotPayload{} = payload) do
    with {:ok, limits} <- Limits.fetch(), do: validate(payload, limits)
  end

  @spec validate(SnapshotPayload.t(), Limits.t()) :: :ok | {:error, PilotError.t()}
  def validate(%SnapshotPayload{} = payload, %Limits{} = limits) do
    with :ok <- within_comparison_count(payload.comparisons, limits) do
      within_matrix_dims(payload.comparisons, limits)
    end
  end

  defp within_comparison_count(comparisons, %Limits{} = limits) do
    count = length(comparisons)

    if count <= limits.snapshot_comparisons do
      :ok
    else
      {:error,
       PilotError.new(
         "validation_failed",
         "invalid_analysis_setting",
         ["payload", "comparisons"],
         "The snapshot comparison count exceeds the configured limit.",
         %{"limit" => limits.snapshot_comparisons, "actual" => count}
       )}
    end
  end

  defp within_matrix_dims(comparisons, %Limits{} = limits) do
    issues =
      comparisons
      |> Enum.with_index()
      |> Enum.flat_map(fn {comparison, index} -> comparison_issues(comparison, index, limits) end)
      |> Enum.take(@max_issues)

    case issues do
      [] -> :ok
      _issues -> {:error, PilotError.validation_failed(issues)}
    end
  end

  defp comparison_issues(%ComparisonEvidence{} = comparison, index, %Limits{} = limits) do
    plan_issues(length(comparison.evidence.alternative.plans), index, limits) ++
      reference_issues(length(comparison.evidence.reference.plans), index, limits) ++
      attack_issues(length(comparison.evidence.attack_seeds), index, limits)
  end

  defp reference_issues(count, index, %Limits{} = limits) do
    row_issues(count, ["payload", "comparisons", index, "evidence", "reference", "plans"], limits)
  end

  defp plan_issues(count, index, %Limits{} = limits) do
    row_issues(
      count,
      ["payload", "comparisons", index, "evidence", "alternative", "plans"],
      limits
    )
  end

  defp row_issues(count, path, %Limits{} = limits) do
    if count <= limits.plans_per_side do
      []
    else
      [
        limit_issue(
          path,
          "The comparison side has more plan rows than the configured limit.",
          limits.plans_per_side,
          count
        )
      ]
    end
  end

  defp attack_issues(count, index, %Limits{} = limits) do
    if count <= limits.attack_columns do
      []
    else
      [
        limit_issue(
          ["payload", "comparisons", index, "evidence", "attack_seeds"],
          "The comparison has more attack columns than the configured limit.",
          limits.attack_columns,
          count
        )
      ]
    end
  end

  defp limit_issue(path, message, limit, actual) do
    %{
      "code" => "invalid_analysis_setting",
      "path" => path,
      "message" => message,
      "details" => %{"limit" => limit, "actual" => actual}
    }
  end
end
