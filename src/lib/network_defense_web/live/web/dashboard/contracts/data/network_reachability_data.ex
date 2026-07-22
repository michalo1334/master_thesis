defmodule NetworkDefenseWeb.Web.Contracts.Data.NetworkReachabilityData do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  embedded_schema do
  end

  @type t :: %__MODULE__{}

  def changeset(schema, attrs), do: cast(schema, attrs, [])
end
