defmodule NetworkDefenseWeb.Web.Contracts.DocumentCatalogItem do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workspace

  @enum_values kind: [:graph, :simulation_report, :optimization_report]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :id, :string
    field :kind, :string
    field :graph_id, :string
    field :graph_revision_id, :string
    field :graph_title, :string
    field :analysis_ids, {:array, :string}, default: []
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
          graph_title: String.t(),
          analysis_ids: [String.t()] | nil,
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
      :graph_title,
      :analysis_ids,
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
    |> validate_inclusion(:kind, ["graph", "simulation_report", "optimization_report"])
    |> NetworkDefense.Contracts.validate_uuid(:id)
    |> NetworkDefense.Contracts.validate_uuid(:graph_id)
    |> NetworkDefense.Contracts.validate_uuid(:graph_revision_id)
    |> validate_change(:analysis_ids, fn :analysis_ids, ids ->
      if Enum.all?(ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
        []
      else
        [analysis_ids: "contains an invalid UUID"]
      end
    end)
    |> NetworkDefense.Contracts.validate_uuid(:output_graph_revision_id)
  end
end
