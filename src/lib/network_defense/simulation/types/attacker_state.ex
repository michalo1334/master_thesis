defmodule NetworkDefense.Simulation.Types.AttackerState do
  @moduledoc false

  @behaviour Ecto.Type

  alias NetworkDefense.AttackerState.AttackerState

  def type, do: :map

  def embed_as(_format), do: :self
  def equal?(left, right), do: left == right

  def cast(%AttackerState{} = state), do: {:ok, state}
  def cast(value), do: load(value)

  def load(value) when is_map(value), do: AttackerState.from_map(value)
  def load(_), do: :error

  def dump(%AttackerState{} = state) do
    {:ok, AttackerState.to_map(state)}
  rescue
    ArgumentError -> :error
  end

  def dump(_), do: :error
end
