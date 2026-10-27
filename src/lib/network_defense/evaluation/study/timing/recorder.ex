defmodule NetworkDefense.Evaluation.Study.Timing.Recorder do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Timing.{Interval, ReplicaTiming}

  @events [:plan_dispatch, :plan_completion, :simulation_dispatch, :simulation_completion]
  @positions 0..4

  @enforce_keys [:tier]
  defstruct tier: nil, readings: %{}, failed: false

  @type event :: :plan_dispatch | :plan_completion | :simulation_dispatch | :simulation_completion
  @type t :: %__MODULE__{
          tier: String.t(),
          readings: %{optional({0..4, event()}) => integer()},
          failed: boolean()
        }

  @spec new(String.t()) :: t()
  def new(tier) when is_binary(tier) and byte_size(tier) > 0,
    do: %__MODULE__{tier: tier}

  @spec record(t(), String.t(), integer(), event(), (-> integer())) ::
          {:ok, t()} | {:error, atom(), t()}
  def record(
        recorder,
        tier,
        position,
        event,
        now_us \\ fn -> System.monotonic_time(:microsecond) end
      )

  def record(%__MODULE__{} = recorder, tier, position, event, now_us) do
    cond do
      recorder.failed ->
        {:error, :terminal_failure, recorder}

      tier != recorder.tier ->
        fail(recorder, :unexpected_tier)

      not is_integer(position) or position not in @positions ->
        fail(recorder, :invalid_position)

      event not in @events ->
        fail(recorder, :invalid_event)

      Map.has_key?(recorder.readings, {position, event}) ->
        {:ok, recorder}

      expected_event(recorder.readings, position) != event ->
        fail(recorder, :out_of_order)

      true ->
        {:ok, %{recorder | readings: Map.put(recorder.readings, {position, event}, now_us.())}}
    end
  end

  @spec complete(t()) ::
          {:ok, [ReplicaTiming.t()]}
          | {:error, :incomplete | :invalid_interval | :terminal_failure}
  def complete(%__MODULE__{failed: true}), do: {:error, :terminal_failure}

  def complete(%__MODULE__{} = recorder) do
    if complete?(recorder.readings) do
      recorder.tier
      |> then(&build_timings(&1, recorder.readings))
    else
      {:error, :incomplete}
    end
  end

  defp build_timings(tier, readings) do
    Enum.reduce_while(@positions, {:ok, []}, fn position, {:ok, timings} ->
      with {:ok, plan_selection} <-
             Interval.between(
               readings[{position, :plan_dispatch}],
               readings[{position, :plan_completion}]
             ),
           {:ok, simulation} <-
             Interval.between(
               readings[{position, :simulation_dispatch}],
               readings[{position, :simulation_completion}]
             ),
           {:ok, total} <-
             Interval.between(
               readings[{position, :plan_dispatch}],
               readings[{position, :simulation_completion}]
             ),
           {:ok, timing} <-
             ReplicaTiming.new(%{
               tier: tier,
               position: position,
               plan_selection: plan_selection,
               simulation: simulation,
               total: total
             }) do
        {:cont, {:ok, [timing | timings]}}
      else
        _ -> {:halt, {:error, :invalid_interval}}
      end
    end)
    |> case do
      {:ok, timings} -> {:ok, Enum.reverse(timings)}
      error -> error
    end
  end

  defp expected_event(readings, position) do
    Enum.find(@events, fn event -> not Map.has_key?(readings, {position, event}) end)
  end

  defp complete?(readings) do
    Enum.all?(@positions, fn position ->
      Enum.all?(@events, &Map.has_key?(readings, {position, &1}))
    end)
  end

  defp fail(recorder, reason), do: {:error, reason, %{recorder | failed: true}}
end
