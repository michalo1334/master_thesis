defmodule NetworkDefense.Graph.Domain.ViewData do
  @moduledoc false

  defstruct [:x_pos, :y_pos, :radius]

  @type t :: %__MODULE__{x_pos: number(), y_pos: number(), radius: number() | nil}

  def from_params(%{"x_pos" => x_pos, "y_pos" => y_pos} = params)
      when is_number(x_pos) and is_number(y_pos) do
    {:ok, %__MODULE__{x_pos: x_pos, y_pos: y_pos, radius: Map.get(params, "radius")}}
  end

  def from_params(nil), do: {:ok, %__MODULE__{x_pos: 0, y_pos: 0}}
  def from_params(_params), do: :error

  def to_params(%__MODULE__{} = view_data) do
    %{"x_pos" => view_data.x_pos, "y_pos" => view_data.y_pos, "radius" => view_data.radius}
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end
end
