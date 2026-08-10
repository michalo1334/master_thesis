defmodule NetworkDefense.Graph.Contracts.Data.SupportsData do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  embedded_schema do
  end

  @type t :: %__MODULE__{}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> validate_required([])
  end
end
