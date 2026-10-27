defmodule NetworkDefense.Evaluation.Study.Timing.TimingSummary do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  # The timing summary of one successful Final result: one tier summary per
  # declared tier. The list follows the declared tier order, so the stored order
  # never depends on map enumeration order.

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Timing.{DurationSummary, TierTiming}

  @type t :: %__MODULE__{tiers: [TierTiming.t()]}

  embedded_schema do
    embeds_many :tiers, TierTiming, on_replace: :delete
  end

  @spec summarize([String.t()], map()) :: {:ok, t()} | {:error, StudyError.t()}
  def summarize(tiers, timing_family) when is_list(tiers) and is_map(timing_family) do
    with :ok <- validate_declared_tiers(tiers),
         :ok <- validate_family(tiers, timing_family),
         {:ok, summaries} <- summarize_tiers(tiers, timing_family) do
      build(summaries)
    end
  end

  def summarize(_tiers, _timing_family), do: {:error, StudyError.final_timing_incomplete()}

  @spec validate_declared_order(t(), [String.t()]) :: :ok | {:error, StudyError.t()}
  def validate_declared_order(%__MODULE__{tiers: [_ | _] = tiers}, declared)
      when is_list(declared) do
    # Every item is checked before any tier field or position is read, so a
    # malformed constructed list returns the bounded error instead of raising.
    with true <- Enum.all?(tiers, &match?(%TierTiming{}, &1)),
         true <- Enum.map(tiers, & &1.tier) == declared,
         true <- contiguous?(tiers) do
      :ok
    else
      _invalid -> {:error, StudyError.final_timing_incomplete()}
    end
  end

  def validate_declared_order(_summary, _declared),
    do: {:error, StudyError.final_timing_incomplete()}

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(summary, attrs) do
    changeset =
      summary
      |> cast(attrs, [])
      |> cast_embed(:tiers, required: true)

    case apply_action(changeset, :validate) do
      {:ok, %__MODULE__{tiers: tiers}} ->
        if contiguous?(tiers),
          do: changeset,
          else: add_error(changeset, :tiers, "must follow tier positions")

      {:error, %Ecto.Changeset{}} ->
        changeset
    end
  end

  defp build(tier_summaries) do
    case %__MODULE__{}
         |> changeset(%{tiers: Enum.map(tier_summaries, &tier_params/1)})
         |> apply_action(:validate) do
      {:ok, %__MODULE__{} = summary} -> {:ok, summary}
      {:error, %Ecto.Changeset{}} -> {:error, StudyError.final_timing_incomplete()}
    end
  end

  defp tier_params(%TierTiming{} = tier_timing) do
    tier_timing
    |> Map.from_struct()
    |> Map.new(fn
      {field, %DurationSummary{} = duration} -> {field, Map.from_struct(duration)}
      {field, value} -> {field, value}
    end)
  end

  defp summarize_tiers(tiers, timing_family) do
    tiers
    |> Enum.with_index()
    |> Enum.reduce_while([], fn {tier, position}, collected ->
      case TierTiming.summarize(tier, position, Map.fetch!(timing_family, tier).timings) do
        {:ok, tier_timing} -> {:cont, [tier_timing | collected]}
        {:error, %StudyError{}} = error -> {:halt, error}
      end
    end)
    |> case do
      {:error, %StudyError{}} = error -> error
      tier_summaries -> {:ok, Enum.reverse(tier_summaries)}
    end
  end

  defp validate_declared_tiers(tiers) do
    valid? =
      tiers != [] and
        Enum.all?(tiers, &(is_binary(&1) and String.trim(&1) != "")) and
        Enum.uniq(tiers) == tiers

    if valid?, do: :ok, else: {:error, StudyError.final_timing_incomplete()}
  end

  defp validate_family(tiers, timing_family) do
    positions_match? =
      tiers
      |> Enum.with_index()
      |> Enum.all?(fn {tier, position} ->
        match?(
          %{tier_position: ^position, timings: timings} when is_list(timings),
          Map.get(timing_family, tier)
        )
      end)

    if Enum.sort(Map.keys(timing_family)) == Enum.sort(tiers) and positions_match?,
      do: :ok,
      else: {:error, StudyError.final_timing_incomplete()}
  end

  defp contiguous?(tiers) do
    Enum.map(tiers, & &1.tier_position) == Enum.to_list(0..(length(tiers) - 1)) and
      tiers |> Enum.map(& &1.tier) |> Enum.uniq() |> length() == length(tiers)
  end
end
