defmodule NetworkDefenseWeb.Web.Contracts.SetReportAnalysisReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workspace

  @enum_values status: [:ok, :not_found, :invalid_analysis, :unmapped_error]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string

    embeds_one :analysis, NetworkDefenseWeb.Web.Contracts.DocumentCatalogAnalysis,
      on_replace: :update
  end

  @type t :: %__MODULE__{
          status: String.t(),
          analysis: NetworkDefenseWeb.Web.Contracts.DocumentCatalogAnalysis.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:analysis)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["ok", "not_found", "invalid_analysis", "unmapped_error"])
  end
end
