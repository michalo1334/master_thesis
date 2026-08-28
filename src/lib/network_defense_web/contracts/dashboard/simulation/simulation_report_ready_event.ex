defmodule NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportReadyEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.FetchSimulationReportReply

  embedded_schema do
    field :document_id, :string
    embeds_one :report, FetchSimulationReportReply, on_replace: :update
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          report: FetchSimulationReportReply.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id])
    |> cast_embed(:report, required: true)
    |> validate_required([:document_id])
    |> Contracts.validate_uuid(:document_id)
  end
end
