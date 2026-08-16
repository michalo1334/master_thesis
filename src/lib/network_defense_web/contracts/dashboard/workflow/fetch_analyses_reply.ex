defmodule NetworkDefenseWeb.Web.Contracts.FetchAnalysesReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workflow

  embedded_schema do
    embeds_many :analyses, NetworkDefenseWeb.Web.Contracts.DocumentCatalogAnalysis,
      on_replace: :delete
  end

  @type t :: %__MODULE__{analyses: [NetworkDefenseWeb.Web.Contracts.DocumentCatalogAnalysis.t()]}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:analyses)
  end
end
