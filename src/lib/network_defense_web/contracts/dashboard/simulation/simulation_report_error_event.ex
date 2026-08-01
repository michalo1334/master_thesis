defmodule NetworkDefenseWeb.Web.Contracts.SimulationReportErrorEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :experiment_id, :string
    field :graph_revision_id, :string
    field :reason, :string
  end

  @type t :: %__MODULE__{
          experiment_id: String.t(),
          graph_revision_id: String.t(),
          reason: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:experiment_id, :graph_revision_id, :reason])
    |> validate_required([:experiment_id, :graph_revision_id, :reason])
  end
end
