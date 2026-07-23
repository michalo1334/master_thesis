defmodule NetworkDefenseWeb.Web.Contracts.Data.RunsData do
  @moduledoc false

  use NetworkDefenseWeb.Contracts

  embedded_schema do
  end

  @type t :: %__MODULE__{}

  def changeset(schema, attrs), do: cast(schema, attrs, [])
end
