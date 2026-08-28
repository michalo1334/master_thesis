defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysisReadyEvent do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysis

  @enum_values mode: [:pilot, :analyze]
  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :document_id, :string
    field :run_id, :string
    field :mode, :string
    embeds_one :analysis, EvaluationAnalysis
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          run_id: String.t(),
          mode: String.t(),
          analysis: EvaluationAnalysis.t()
        }
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id, :run_id, :mode])
    |> cast_embed(:analysis)
    |> validate_required([:document_id, :run_id, :mode, :analysis])
    |> validate_inclusion(:mode, ["pilot", "analyze"])
    |> Contracts.validate_uuid(:run_id)
  end
end
