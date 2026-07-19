defmodule NetworkDefense.Simulation.Types.Seed do
  @moduledoc false

  @behaviour Ecto.Type

  def type, do: :map

  def embed_as(_format), do: :self
  def equal?(left, right), do: left == right

  def cast(seed) when is_tuple(seed), do: {:ok, seed}
  def cast(_), do: :error

  def load(%{"algorithm" => "exsss", "state" => [first, second]})
      when is_integer(first) and is_integer(second) do
    {:ok, :rand.seed_s({:exsss, Enum.reduce([first], second, &[&1 | &2])})}
  end

  def load(_), do: :error

  def dump(seed) when is_tuple(seed) do
    case :rand.export_seed_s(seed) do
      {:exsss, [first | second]} when is_integer(first) and is_integer(second) ->
        {:ok, %{"algorithm" => "exsss", "state" => [first, second]}}

      _seed ->
        :error
    end
  end

  def dump(_), do: :error
end
