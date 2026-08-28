defmodule NetworkDefenseWeb.Contracts.Dashboard.Workspace.DocumentCatalogItem do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workspace

  alias NetworkDefense.DocumentCatalog.Kind

  @enum_values kind: Kind.values()

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :id, :string
    field :kind, :string
    field :graph_id, :string
    field :graph_revision_id, :string
    field :parent_revision_id, :string
    field :graph_title, :string
    field :manifest_id, :string
    field :manifest_title, :string

    field :revision_kind, :string
    field :revision_number, :integer
    field :strategy, :string
    field :output_graph_revision_id, :string
    field :output_revision_kind, :string
    field :output_revision_number, :integer
    field :created_at, :string
  end

  @type t :: %__MODULE__{
          id: String.t(),
          kind: String.t(),
          graph_id: String.t(),
          graph_revision_id: String.t(),
          parent_revision_id: String.t() | nil,
          graph_title: String.t(),
          manifest_id: String.t() | nil,
          manifest_title: String.t() | nil,
          revision_kind: String.t(),
          revision_number: pos_integer(),
          strategy: String.t() | nil,
          output_graph_revision_id: String.t() | nil,
          output_revision_kind: String.t() | nil,
          output_revision_number: pos_integer() | nil,
          created_at: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :id,
      :kind,
      :graph_id,
      :graph_revision_id,
      :parent_revision_id,
      :graph_title,
      :manifest_id,
      :manifest_title,
      :revision_kind,
      :revision_number,
      :strategy,
      :output_graph_revision_id,
      :output_revision_kind,
      :output_revision_number,
      :created_at
    ])
    |> validate_required([
      :id,
      :kind,
      :graph_id,
      :graph_revision_id,
      :graph_title,
      :revision_kind,
      :revision_number,
      :created_at
    ])
    |> validate_inclusion(:kind, Kind.strings())
    |> validate_length(:manifest_id, min: 1, max: 255)
    |> validate_length(:manifest_title, min: 1, max: 255)
    |> NetworkDefense.Contracts.validate_uuid(:id)
    |> NetworkDefense.Contracts.validate_uuid(:graph_id)
    |> NetworkDefense.Contracts.validate_uuid(:graph_revision_id)
    |> NetworkDefense.Contracts.validate_uuid(:parent_revision_id)
    |> NetworkDefense.Contracts.validate_uuid(:output_graph_revision_id)
  end
end
