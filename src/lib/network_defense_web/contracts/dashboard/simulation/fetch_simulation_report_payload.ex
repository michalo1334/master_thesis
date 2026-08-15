defmodule NetworkDefenseWeb.Web.Contracts.FetchSimulationReportPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :document_id, :string
    field :experiment_id, :string
    field :graph_revision_id, :string
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          experiment_id: String.t(),
          graph_revision_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id, :experiment_id, :graph_revision_id])
    |> validate_required([:document_id, :experiment_id, :graph_revision_id])
    |> Contracts.validate_uuid(:document_id)
    |> validate_length(:experiment_id, min: 1)
    |> validate_length(:graph_revision_id, min: 1)
    |> Contracts.validate_uuid(:experiment_id)
    |> Contracts.validate_uuid(:graph_revision_id)
  end
end
