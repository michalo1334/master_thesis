defmodule NetworkDefenseWeb.Web.Contracts.FetchAnalysesPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workflow

  embedded_schema do
  end

  @type t :: %__MODULE__{}

  def changeset(schema, attrs), do: cast(schema, attrs, [])
end
