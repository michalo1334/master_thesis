defmodule NetworkDefense.Evaluation.Study.Timing.ReplicaTiming do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Timing.Interval

  @enforce_keys [:tier, :position, :plan_selection, :simulation, :total]
  defstruct [:tier, :position, :plan_selection, :simulation, :total]

  @type t :: %__MODULE__{
          tier: String.t(),
          position: 0..4,
          plan_selection: Interval.t(),
          simulation: Interval.t(),
          total: Interval.t()
        }

  @spec new(map()) :: {:ok, t()} | :error
  def new(attrs) when is_map(attrs) do
    with {:ok, tier} <- fetch_tier(attrs),
         {:ok, position} <- fetch_position(attrs),
         {:ok, plan_selection} <- fetch_interval(attrs, :plan_selection),
         {:ok, simulation} <- fetch_interval(attrs, :simulation),
         {:ok, total} <- fetch_interval(attrs, :total) do
      {:ok,
       %__MODULE__{
         tier: tier,
         position: position,
         plan_selection: plan_selection,
         simulation: simulation,
         total: total
       }}
    else
      _ -> :error
    end
  end

  def new(_attrs), do: :error

  defp fetch_tier(attrs) do
    case Map.get(attrs, :tier, Map.get(attrs, "tier")) do
      tier when is_binary(tier) ->
        if String.trim(tier) != "", do: {:ok, tier}, else: :error

      _ ->
        :error
    end
  end

  defp fetch_position(attrs) do
    case Map.get(attrs, :position, Map.get(attrs, "position")) do
      position when is_integer(position) and position in 0..4 -> {:ok, position}
      _ -> :error
    end
  end

  defp fetch_interval(attrs, field) do
    case Map.get(attrs, field, Map.get(attrs, Atom.to_string(field))) do
      %Interval{elapsed_us: elapsed} = interval when is_integer(elapsed) and elapsed >= 0 ->
        {:ok, interval}

      _ ->
        :error
    end
  end
end
