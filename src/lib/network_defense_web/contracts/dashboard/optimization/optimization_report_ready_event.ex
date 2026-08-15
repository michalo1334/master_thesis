defmodule NetworkDefenseWeb.Web.Contracts.OptimizationReportReadyEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  alias NetworkDefenseWeb.Web.Contracts.FetchOptimizationReportReply

  embedded_schema do
    field :document_id, :string
    embeds_one :report, FetchOptimizationReportReply, on_replace: :update
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          report: FetchOptimizationReportReply.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id])
    |> cast_embed(:report, required: true)
    |> validate_required([:document_id])
    |> Contracts.validate_uuid(:document_id)
  end
end
