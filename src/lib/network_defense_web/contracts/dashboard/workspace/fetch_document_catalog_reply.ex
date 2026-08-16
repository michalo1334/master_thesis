defmodule NetworkDefenseWeb.Web.Contracts.FetchDocumentCatalogReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workspace

  embedded_schema do
    embeds_many :items, NetworkDefenseWeb.Web.Contracts.DocumentCatalogItem, on_replace: :delete
  end

  @type t :: %__MODULE__{items: [NetworkDefenseWeb.Web.Contracts.DocumentCatalogItem.t()]}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:items)
  end
end
