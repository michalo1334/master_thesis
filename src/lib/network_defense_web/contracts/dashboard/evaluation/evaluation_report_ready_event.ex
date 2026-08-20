defmodule NetworkDefenseWeb.Web.Contracts.EvaluationReportReadyEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Web.Contracts.EvaluationReport

  embedded_schema do
    field :document_id, :string
    embeds_one :report, EvaluationReport
  end

  @type t :: %__MODULE__{document_id: String.t(), report: EvaluationReport.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id])
    |> cast_embed(:report)
    |> validate_required([:document_id, :report])
  end
end
