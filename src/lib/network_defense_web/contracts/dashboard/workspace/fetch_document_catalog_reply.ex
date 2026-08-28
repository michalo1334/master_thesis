defmodule NetworkDefenseWeb.Contracts.Dashboard.Workspace.FetchDocumentCatalogReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workspace

  embedded_schema do
    embeds_many :items, NetworkDefenseWeb.Contracts.Dashboard.Workspace.DocumentCatalogItem,
      on_replace: :delete

    embeds_many :related_items,
                NetworkDefenseWeb.Contracts.Dashboard.Workspace.DocumentCatalogItem,
                on_replace: :delete

    field :total_count, :integer, default: 0

    embeds_one :filter_options,
               NetworkDefenseWeb.Contracts.Dashboard.Workspace.DocumentCatalogFilterOptions,
               on_replace: :update
  end

  @type t :: %__MODULE__{
          items: [NetworkDefenseWeb.Contracts.Dashboard.Workspace.DocumentCatalogItem.t()],
          related_items: [NetworkDefenseWeb.Contracts.Dashboard.Workspace.DocumentCatalogItem.t()],
          total_count: non_neg_integer(),
          filter_options:
            NetworkDefenseWeb.Contracts.Dashboard.Workspace.DocumentCatalogFilterOptions.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:total_count])
    |> cast_embed(:items)
    |> cast_embed(:related_items)
    |> cast_embed(:filter_options, required: true)
    |> validate_number(:total_count, greater_than_or_equal_to: 0)
  end
end
