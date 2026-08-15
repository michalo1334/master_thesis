defmodule NetworkDefenseWeb.Web.Contracts.WorkflowFailedEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workflow

  alias NetworkDefenseWeb.Web.Contracts.DashboardError

  embedded_schema do
    field :workflow_id, :string
    embeds_one :error, DashboardError, on_replace: :update
  end

  @type t :: %__MODULE__{workflow_id: String.t(), error: DashboardError.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:workflow_id])
    |> cast_embed(:error, required: true)
    |> validate_required(:workflow_id)
  end
end
