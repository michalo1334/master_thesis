defmodule NetworkDefense.Evaluation2.Study.Result.Timing do
  @moduledoc """
  Measured Final timing of one study result.

  One clock measures three boundaries for each measured replica of every
  declared tier. A tier holds exactly five replicas, and warm-up stays outside
  the measured values.

  The map is keyed by the closed tier order of
  `NetworkDefense.Evaluation2.Study.Tier`. Median and range are derived operations
  on the stored raw values, so reporting keeps every observation.
  """

  alias NetworkDefense.Evaluation2.Study.Result.Timing.Tier
  alias NetworkDefense.Evaluation2.Study.Tier, as: StudyTier

  @typedoc "One measured elapsed time in microseconds."
  @type elapsed_us :: non_neg_integer()

  @typedoc "Measured timing of every declared tier."
  @type by_tier :: %{StudyTier.t() => Tier.t()}

  @type boundary :: :plan_selection | :simulation | :total
  @type measurements :: %{
          required(0) => elapsed_us(),
          required(1) => elapsed_us(),
          required(2) => elapsed_us(),
          required(3) => elapsed_us(),
          required(4) => elapsed_us()
        }

  @type t :: %__MODULE__{by_tier: by_tier()}

  defstruct [:by_tier]

  @doc "Return the measured values keyed by replica position."
  @spec measurements(t(), StudyTier.t(), boundary()) :: measurements()
  def measurements(%__MODULE__{by_tier: by_tier}, tier, boundary) do
    field =
      %{plan_selection: :plan_selection_us, simulation: :simulation_us, total: :total_us}
      |> Map.fetch!(boundary)

    replicas = by_tier |> Map.fetch!(tier) |> Map.fetch!(:replicas)

    Map.new(0..4, fn position ->
      {position, replicas |> Map.fetch!(position) |> Map.fetch!(field)}
    end)
  end

  @doc "Return the median measured duration in microseconds."
  @spec median(t(), StudyTier.t(), boundary()) :: elapsed_us()
  def median(timing, tier, boundary) do
    [_, _, median, _, _] = timing |> measurements(tier, boundary) |> Map.values() |> Enum.sort()
    median
  end

  @doc "Return the minimum and maximum measured durations in microseconds."
  @spec range(t(), StudyTier.t(), boundary()) :: {elapsed_us(), elapsed_us()}
  def range(timing, tier, boundary) do
    timing |> measurements(tier, boundary) |> Map.values() |> Enum.min_max()
  end
end
