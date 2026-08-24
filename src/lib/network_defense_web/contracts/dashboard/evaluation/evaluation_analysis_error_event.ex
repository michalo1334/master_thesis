defmodule NetworkDefenseWeb.Web.Contracts.EvaluationAnalysisErrorEvent do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation
  alias NetworkDefenseWeb.Web.Contracts.DashboardError

  @enum_values mode: [:pilot, :analyze]
  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :document_id, :string
    field :run_id, :string
    field :mode, :string
    embeds_one :error, DashboardError
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          run_id: String.t(),
          mode: String.t(),
          error: DashboardError.t()
        }
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id, :run_id, :mode])
    |> cast_embed(:error)
    |> validate_required([:document_id, :run_id, :mode, :error])
    |> validate_inclusion(:mode, ["pilot", "analyze"])
    |> NetworkDefense.Contracts.validate_uuid(:run_id)
  end
end
