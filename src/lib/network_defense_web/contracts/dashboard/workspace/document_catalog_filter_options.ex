defmodule NetworkDefenseWeb.Contracts.Dashboard.Workspace.DocumentCatalogFilterOptions do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workspace

  alias NetworkDefenseWeb.Contracts.Dashboard.Workspace.DocumentCatalogGraphFilterOption

  embedded_schema do
    field :types, {:array, :string}, default: []

    embeds_many :graphs,
                DocumentCatalogGraphFilterOption,
                on_replace: :delete

    field :strategies, {:array, :string}, default: []
    field :revision_kinds, {:array, :string}, default: []
  end

  @type t :: %__MODULE__{
          types: [String.t()],
          graphs: [
            DocumentCatalogGraphFilterOption.t()
          ],
          strategies: [String.t()],
          revision_kinds: [String.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:types, :strategies, :revision_kinds])
    |> cast_embed(:graphs)
  end
end
