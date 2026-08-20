defmodule NetworkDefenseWeb.Web.Contracts.EvaluationReportErrorEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Web.Contracts.DashboardError

  embedded_schema do
    field :document_id, :string
    field :run_id, :string
    embeds_one :error, DashboardError
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          run_id: String.t(),
          error: DashboardError.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id, :run_id])
    |> cast_embed(:error)
    |> validate_required([:document_id, :run_id, :error])
    |> NetworkDefense.Contracts.validate_uuid(:run_id)
  end
end
