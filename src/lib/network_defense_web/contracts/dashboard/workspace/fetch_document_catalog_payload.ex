defmodule NetworkDefenseWeb.Web.Contracts.FetchDocumentCatalogPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workspace

  alias NetworkDefense.DocumentCatalog.Kind

  embedded_schema do
    field :search, :string, default: ""
    field :types, {:array, :string}, default: []
    field :graph_ids, {:array, :string}, default: []
    field :analysis_ids, {:array, :string}, default: []
    field :strategies, {:array, :string}, default: []
    field :revision_kinds, {:array, :string}, default: []
    field :limit, :integer, default: 50
    field :offset, :integer, default: 0
  end

  @type t :: %__MODULE__{
          search: String.t(),
          types: [String.t()],
          graph_ids: [String.t()],
          analysis_ids: [String.t()],
          strategies: [String.t()],
          revision_kinds: [String.t()],
          limit: pos_integer(),
          offset: non_neg_integer()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :search,
      :types,
      :graph_ids,
      :analysis_ids,
      :strategies,
      :revision_kinds,
      :limit,
      :offset
    ])
    |> validate_length(:search, max: 255)
    |> validate_value_list(:types, Kind.strings())
    |> validate_value_list(:revision_kinds, ["initial", "edit", "optimization"])
    |> validate_uuid_list(:graph_ids)
    |> validate_uuid_list(:analysis_ids)
    |> validate_number(:limit, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_number(:offset, greater_than_or_equal_to: 0)
  end

  defp validate_uuid_list(changeset, field) do
    validate_change(changeset, field, fn ^field, ids ->
      if Enum.all?(ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
        []
      else
        [{field, "contains an invalid UUID"}]
      end
    end)
  end

  defp validate_value_list(changeset, field, allowed_values) do
    validate_change(changeset, field, fn ^field, values ->
      if Enum.all?(values, &(&1 in allowed_values)) do
        []
      else
        [{field, "contains an invalid value"}]
      end
    end)
  end
end
