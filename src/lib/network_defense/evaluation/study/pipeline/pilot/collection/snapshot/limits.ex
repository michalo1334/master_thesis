defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Snapshot.Limits do
  @moduledoc false

  alias NetworkDefense.Evaluation.SnapshotDimensions
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Error, as: PilotError
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Limits

  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.Evidence.Contracts.ComparisonEvidence
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Snapshot.Contracts.Payload

  # Dimension checks for stored evidence.
  #
  # Creation and every read call this module with the required application
  # limits. The check covers the comparison count and the stored matrix shape:
  # plan rows on each side and attack columns for every comparison. The check
  # never changes or truncates the payload.

  @spec validate(Payload.t()) :: :ok | {:error, PilotError.t()}
  def validate(%Payload{} = payload) do
    with {:ok, limits} <- Limits.fetch(), do: validate(payload, limits)
  end

  @spec validate(Payload.t(), Limits.t()) :: :ok | {:error, PilotError.t()}
  def validate(%Payload{} = payload, %Limits{} = limits) do
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
