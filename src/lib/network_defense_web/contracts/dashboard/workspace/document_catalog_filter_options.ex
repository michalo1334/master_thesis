defmodule NetworkDefenseWeb.Web.Contracts.DocumentCatalogFilterOptions do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workspace

  embedded_schema do
    field :types, {:array, :string}, default: []

    embeds_many :graphs, NetworkDefenseWeb.Web.Contracts.DocumentCatalogGraphFilterOption,
      on_replace: :delete

    embeds_many :analyses, NetworkDefenseWeb.Web.Contracts.DocumentCatalogAnalysis,
      on_replace: :delete

    field :strategies, {:array, :string}, default: []
    field :revision_kinds, {:array, :string}, default: []
  end

  @type t :: %__MODULE__{
          types: [String.t()],
          graphs: [NetworkDefenseWeb.Web.Contracts.DocumentCatalogGraphFilterOption.t()],
          analyses: [NetworkDefenseWeb.Web.Contracts.DocumentCatalogAnalysis.t()],
          strategies: [String.t()],
          revision_kinds: [String.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:types, :strategies, :revision_kinds])
    |> cast_embed(:graphs)
    |> cast_embed(:analyses)
  end
end
