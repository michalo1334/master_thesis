defmodule NetworkDefenseWeb.Contracts.Dashboard.Simulation.RunSimulationReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  alias NetworkDefenseWeb.Contracts.Dashboard.DashboardError

  def contract_meta, do: Contracts.run_reply_meta()

  embedded_schema do
    field :status, :string
    field :graph_revision_id, :string
    field :correlation_id, :string
    field :run_id, :string
    embeds_one :error, DashboardError, on_replace: :update
  end

  @type t :: %__MODULE__{
          status: String.t(),
          graph_revision_id: String.t(),
          correlation_id: String.t(),
          run_id: String.t(),
          error: DashboardError.t() | nil
        }

  def changeset(schema, attrs), do: Contracts.run_reply_changeset(schema, attrs)
end
