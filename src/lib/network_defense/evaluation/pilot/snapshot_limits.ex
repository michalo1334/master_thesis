defmodule NetworkDefense.Evaluation.Pilot.SnapshotLimits do
  @moduledoc false

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    ComparisonEvidence,
    PilotError,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Pilot.Limits
  alias NetworkDefense.Evaluation.SnapshotDimensions

  # Dimension checks for stored evidence.
  #
  # Creation and every read call this module with the required application
  # limits. The check covers the comparison count and the stored matrix shape:
  # plan rows on each side and attack columns for every comparison. The check
  # never changes or truncates the payload.

  @spec validate(SnapshotPayload.t()) :: :ok | {:error, PilotError.t()}
  def validate(%SnapshotPayload{} = payload) do
    with {:ok, limits} <- Limits.fetch(), do: validate(payload, limits)
  end

  @spec validate(SnapshotPayload.t(), Limits.t()) :: :ok | {:error, PilotError.t()}
  def validate(%SnapshotPayload{} = payload, %Limits{} = limits) do
    payload.comparisons
    |> SnapshotDimensions.validate(
      limits.snapshot_comparisons,
      &comparison_issues(&1, &2, limits)
    )
    |> translate_result()
  end

  defp translate_result(:ok), do: :ok

  defp translate_result({:comparison_limit, issue}) do
    {:error,
     PilotError.new(
       "validation_failed",
       issue["code"],
       issue["path"],
       issue["message"],
       issue["details"]
     )}
  end

  defp translate_result({:matrix_limits, issues}),
    do: {:error, PilotError.validation_failed(issues)}

  defp comparison_issues(%ComparisonEvidence{} = comparison, index, %Limits{} = limits) do
    SnapshotDimensions.comparison_issues(
      comparison.evidence,
      index,
      limits.plans_per_side,
      limits.attack_columns
    )
  end
end
