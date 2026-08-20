defmodule NetworkDefenseWeb.Web.Contracts.FetchEvaluationReportPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :document_id, :string
    field :run_id, :string
  end

  @type t :: %__MODULE__{document_id: String.t(), run_id: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id, :run_id])
    |> validate_required([:document_id, :run_id])
    |> NetworkDefense.Contracts.validate_uuid(:run_id)
  end
end
