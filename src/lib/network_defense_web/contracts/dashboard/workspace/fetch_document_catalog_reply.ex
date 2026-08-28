defmodule NetworkDefenseWeb.Contracts.Dashboard.Workspace.FetchDocumentCatalogReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workspace

  alias NetworkDefenseWeb.Contracts.Dashboard.Workspace.DocumentCatalogFilterOptions
  alias NetworkDefenseWeb.Contracts.Dashboard.Workspace.DocumentCatalogItem

  embedded_schema do
    embeds_many :items, DocumentCatalogItem, on_replace: :delete

    embeds_many :related_items,
                DocumentCatalogItem,
                on_replace: :delete

    field :total_count, :integer, default: 0

    embeds_one :filter_options,
               DocumentCatalogFilterOptions,
               on_replace: :update
  end

  @type t :: %__MODULE__{
          items: [DocumentCatalogItem.t()],
          related_items: [DocumentCatalogItem.t()],
          total_count: non_neg_integer(),
          filter_options: DocumentCatalogFilterOptions.t()
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
