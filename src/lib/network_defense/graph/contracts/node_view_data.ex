defmodule NetworkDefense.Graph.Contracts.NodeViewData do
  @moduledoc false

  use NetworkDefense.Contracts, dashboard: true

  embedded_schema do
    field :x_pos, :float
    field :y_pos, :float
    field :radius, :float
  end

  @type t :: %__MODULE__{
          x_pos: float(),
          y_pos: float(),
          radius: float() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:x_pos, :y_pos, :radius])
    |> validate_required([:x_pos, :y_pos])
  end
end
