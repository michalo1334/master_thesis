defmodule NetworkDefenseWeb.Web.Contracts.RequestEvaluationAnalysisPayload do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  @enum_values mode: [:pilot, :analyze]
  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :document_id, :string
    field :run_id, :string
    field :mode, :string
  end

  @type t :: %__MODULE__{document_id: String.t(), run_id: String.t(), mode: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id, :run_id, :mode])
    |> validate_required([:document_id, :run_id, :mode])
    |> validate_inclusion(:mode, ["pilot", "analyze"])
    |> NetworkDefense.Contracts.validate_uuid(:run_id)
  end
end
