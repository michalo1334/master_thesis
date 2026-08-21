defmodule NetworkDefenseWeb.Web.Contracts.FetchRunsPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :runs

  embedded_schema do
  end

  @type t :: %__MODULE__{}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
  end
end
