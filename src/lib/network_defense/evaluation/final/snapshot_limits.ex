defmodule NetworkDefense.Evaluation.Final.SnapshotLimits do
  @moduledoc false

  alias NetworkDefense.Evaluation.Final.Contracts.{
    ComparisonEvidence,
    FinalError,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Pilot.Limits
  alias NetworkDefense.Evaluation.SnapshotDimensions

  # Dimension checks for stored Final evidence.
  #
  # Creation and every read call this module with the required application
  # limits. Stage 4 limits are deployment resource caps, not scientific
  # settings, so this check reuses the Stage 4 limit configuration.
  #
  # The check covers the comparison count and the stored matrix shape: plan rows
  # on each side and attack columns for every comparison. The check never
  # changes or truncates the payload.

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
     FinalError.new(
       "validation_failed",
       issue["code"],
       issue["path"],
       issue["message"],
       issue["details"]
     )}
  end

  defp translate_result({:matrix_limits, issues}),
    do: {:error, FinalError.validation_failed(issues)}

  defp comparison_issues(%ComparisonEvidence{} = comparison, index, %Limits{} = limits) do
    SnapshotDimensions.comparison_issues(
      comparison.evidence,
      index,
      limits.plans_per_side,
      limits.attack_columns
    )
  end
end
