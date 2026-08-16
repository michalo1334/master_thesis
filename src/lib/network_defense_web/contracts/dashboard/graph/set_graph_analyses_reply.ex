defmodule NetworkDefenseWeb.Web.Contracts.SetGraphAnalysesReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  @enum_values status: [:ok, :not_found, :invalid_graph, :invalid_analyses, :unmapped_error]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string

    embeds_many :analyses, NetworkDefenseWeb.Web.Contracts.DocumentCatalogAnalysis,
      on_replace: :delete
  end

  @type t :: %__MODULE__{
          status: String.t(),
          analyses: [NetworkDefenseWeb.Web.Contracts.DocumentCatalogAnalysis.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:analyses)
    |> validate_required([:status])
    |> validate_inclusion(:status, [
      "ok",
      "not_found",
      "invalid_graph",
      "invalid_analyses",
      "unmapped_error"
    ])
  end
end
