defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysis do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.{
    EvaluationAnalysisCapabilityRow,
    EvaluationAnalysisFeasibilityRow,
    EvaluationAnalysisMetadata,
    EvaluationAnalysisPilotRow,
    EvaluationAnalysisPrimaryRow,
    EvaluationAnalysisSecondaryRow
  }

  embedded_schema do
    embeds_one :metadata, EvaluationAnalysisMetadata
    embeds_many :pilot_comparison_pass, EvaluationAnalysisPilotRow, on_replace: :delete
    embeds_many :primary_results, EvaluationAnalysisPrimaryRow, on_replace: :delete
    embeds_many :secondary_results, EvaluationAnalysisSecondaryRow, on_replace: :delete
    embeds_many :capability_results, EvaluationAnalysisCapabilityRow, on_replace: :delete
    embeds_many :feasibility_summary, EvaluationAnalysisFeasibilityRow, on_replace: :delete
  end

  @type t :: %__MODULE__{
          metadata: EvaluationAnalysisMetadata.t(),
          pilot_comparison_pass: [EvaluationAnalysisPilotRow.t()],
          primary_results: [EvaluationAnalysisPrimaryRow.t()],
          secondary_results: [EvaluationAnalysisSecondaryRow.t()],
          capability_results: [EvaluationAnalysisCapabilityRow.t()],
          feasibility_summary: [EvaluationAnalysisFeasibilityRow.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:metadata)
    |> cast_embed(:pilot_comparison_pass)
    |> cast_embed(:primary_results)
    |> cast_embed(:secondary_results)
    |> cast_embed(:capability_results)
    |> cast_embed(:feasibility_summary)
    |> validate_required([:metadata])
  end
end
