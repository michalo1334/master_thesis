defmodule NetworkDefense.Graph.Contracts.Data.NetworkReachabilityData do
  @moduledoc false

  use NetworkDefense.Contracts, dashboard: true

  embedded_schema do
  end

  @type t :: %__MODULE__{}

  def changeset(schema, attrs), do: cast(schema, attrs, [])
end
