defmodule NetworkDefense.Evaluation.Final.SnapshotLimits do
  @moduledoc false

  alias NetworkDefense.Evaluation.Final.Contracts.{
    ComparisonEvidence,
    FinalError,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Pilot.Limits

  # Dimension checks for stored Final evidence.
  #
  # Creation and every read call this module with the required application
  # limits. Stage 4 limits are deployment resource caps, not scientific
  # settings, so this check reuses the Stage 4 limit configuration.
  #
  # The check covers the comparison count and the stored matrix shape: plan rows
  # on each side and attack columns for every comparison. The check never
  # changes or truncates the payload.

  @max_issues 50

  @doc """
  Read the shared Stage 4 snapshot caps as an owning Final configuration.

  Stage 4 owns the shared snapshot, dimension, and work settings, so Final
  reuses its loader. A missing or malformed shared configuration is still a
  Final configuration failure at a Final boundary, so this wrapper converts the
  foreign Pilot error once for every Final caller.
  """
  @spec limits() :: {:ok, Limits.t()} | {:error, FinalError.t()}
  def limits do
    case Limits.fetch() do
      {:ok, %Limits{} = limits} ->
        {:ok, limits}

      {:error, _pilot_error} ->
        {:error,
         FinalError.configuration_invalid(
           "The shared snapshot limits are not configured or not valid."
         )}
    end
  end

  @spec validate(SnapshotPayload.t()) :: :ok | {:error, FinalError.t()}
  def validate(%SnapshotPayload{} = payload) do
    with {:ok, limits} <- limits(), do: validate(payload, limits)
  end

  @spec validate(SnapshotPayload.t(), Limits.t()) :: :ok | {:error, FinalError.t()}
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
       FinalError.new(
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
      _issues -> {:error, FinalError.validation_failed(issues)}
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
