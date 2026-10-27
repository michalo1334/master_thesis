defmodule NetworkDefense.Evaluation.Study.Timing.TierTiming do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  # The timing summary of one declared Final tier. The five measured replicas are
  # positions 0..4 of that tier; the warm-up position stays outside the summary.
  # The total duration is the accepted replica total, never a sum of the others.

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  alias NetworkDefense.Evaluation.Study.Timing.{
    DurationSummary,
    Interval,
    ReplicaTiming
  }

  @measured_positions [0, 1, 2, 3, 4]

  @type t :: %__MODULE__{
          tier: String.t(),
          tier_position: non_neg_integer(),
          plan_selection: DurationSummary.t(),
          simulation: DurationSummary.t(),
          total: DurationSummary.t()
        }

  embedded_schema do
    field :tier, :string
    field :tier_position, :integer

    embeds_one :plan_selection, DurationSummary, on_replace: :update
    embeds_one :simulation, DurationSummary, on_replace: :update
    embeds_one :total, DurationSummary, on_replace: :update
  end

  @spec summarize(String.t(), non_neg_integer(), [ReplicaTiming.t()]) ::
          {:ok, t()} | {:error, StudyError.t()}
  def summarize(tier, tier_position, timings)
      when is_binary(tier) and tier_position >= 0 and is_list(timings) do
    with :ok <- validate_measured_timings(tier, timings),
         {:ok, plan_selection} <-
           DurationSummary.summarize(elapsed_values(timings, :plan_selection)),
         {:ok, simulation} <- DurationSummary.summarize(elapsed_values(timings, :simulation)),
         {:ok, total} <- DurationSummary.summarize(elapsed_values(timings, :total)) do
      validate_summary(%__MODULE__{
        tier: tier,
        tier_position: tier_position,
        plan_selection: plan_selection,
        simulation: simulation,
        total: total
      })
    end
  end

  def summarize(_tier, _tier_position, _timings),
    do: {:error, StudyError.final_timing_incomplete()}

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(tier_timing, attrs) do
    tier_timing
    |> cast(attrs, [:tier, :tier_position])
    |> validate_required([:tier, :tier_position])
    |> validate_change(:tier, &validate_tier/2)
    |> validate_number(:tier_position, greater_than_or_equal_to: 0)
    |> cast_embed(:plan_selection, required: true)
    |> cast_embed(:simulation, required: true)
    |> cast_embed(:total, required: true)
  end

  defp validate_summary(%__MODULE__{} = tier_timing) do
    attrs = %{
      tier: tier_timing.tier,
      tier_position: tier_timing.tier_position,
      plan_selection: Map.from_struct(tier_timing.plan_selection),
      simulation: Map.from_struct(tier_timing.simulation),
      total: Map.from_struct(tier_timing.total)
    }

    case tier_timing |> changeset(attrs) |> apply_action(:validate) do
      {:ok, %__MODULE__{} = summary} -> {:ok, summary}
      {:error, %Ecto.Changeset{}} -> {:error, StudyError.final_timing_incomplete()}
    end
  end

  defp validate_tier(:tier, tier) do
    if String.trim(tier) == "", do: [tier: "must not be blank"], else: []
  end

  defp validate_measured_timings(tier, timings) do
    positions =
      Enum.map(timings, fn
        %ReplicaTiming{tier: ^tier, position: position} = timing ->
          if complete_intervals?(timing), do: position, else: :invalid

        _other ->
          :invalid
      end)

    if positions == @measured_positions,
      do: :ok,
      else: {:error, StudyError.final_timing_incomplete()}
  end

  defp complete_intervals?(%ReplicaTiming{} = timing) do
    Enum.all?([timing.plan_selection, timing.simulation, timing.total], &interval?/1)
  end

  defp interval?(%Interval{elapsed_us: elapsed_us}),
    do: is_integer(elapsed_us) and elapsed_us >= 0

  defp interval?(_other), do: false

  defp elapsed_values(timings, field) do
    Enum.map(timings, fn timing -> Map.fetch!(Map.fetch!(timing, field), :elapsed_us) end)
  end
end
