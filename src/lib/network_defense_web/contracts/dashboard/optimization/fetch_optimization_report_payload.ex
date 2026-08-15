defmodule NetworkDefenseWeb.Web.Contracts.FetchOptimizationReportPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  embedded_schema do
    field :document_id, :string
    field :optimization_id, :string
    field :graph_revision_id, :string
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          optimization_id: String.t(),
          graph_revision_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id, :optimization_id, :graph_revision_id])
    |> validate_required([:document_id, :optimization_id, :graph_revision_id])
    |> Contracts.validate_uuid(:document_id)
    |> validate_length(:optimization_id, min: 1)
    |> validate_length(:graph_revision_id, min: 1)
    |> Contracts.validate_uuid(:optimization_id)
    |> Contracts.validate_uuid(:graph_revision_id)
  end
end
