defmodule NetworkDefenseWeb.Web.Contracts.FetchSimulationReportPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :experiment_id, :string
    field :graph_revision_id, :string
  end

  @type t :: %__MODULE__{
          experiment_id: String.t(),
          graph_revision_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:experiment_id, :graph_revision_id])
    |> validate_required([:experiment_id, :graph_revision_id])
    |> validate_length(:experiment_id, min: 1)
    |> validate_length(:graph_revision_id, min: 1)
    |> Contracts.validate_uuid(:experiment_id)
    |> Contracts.validate_uuid(:graph_revision_id)
  end
end
