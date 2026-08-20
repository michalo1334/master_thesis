defmodule NetworkDefenseWeb.Web.Contracts.EvaluationCompletedEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :run_id, :string
    field :manifest_id, :string
    field :manifest_title, :string
    field :source_graph_revision_id, :string
  end

  @type t :: %__MODULE__{
          run_id: String.t(),
          manifest_id: String.t(),
          manifest_title: String.t(),
          source_graph_revision_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:run_id, :manifest_id, :manifest_title, :source_graph_revision_id])
    |> validate_required([:run_id, :manifest_id, :manifest_title, :source_graph_revision_id])
    |> NetworkDefense.Contracts.validate_uuid(:run_id)
    |> NetworkDefense.Contracts.validate_uuid(:source_graph_revision_id)
  end
end
