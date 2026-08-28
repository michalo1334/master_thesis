defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationReport do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationExperimentSummary
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationPlanSummary

  embedded_schema do
    field :run_id, :string
    field :status, :string
    field :failure_reason, :string
    field :manifest_id, :string
    field :manifest_title, :string
    field :graph_id, :string
    field :source_graph_revision_id, :string
    field :source_graph_title, :string
    embeds_many :plans, EvaluationPlanSummary, on_replace: :delete
    embeds_many :experiments, EvaluationExperimentSummary, on_replace: :delete
  end

  @type t :: %__MODULE__{
          run_id: String.t(),
          status: String.t(),
          failure_reason: String.t() | nil,
          manifest_id: String.t(),
          manifest_title: String.t(),
          graph_id: String.t(),
          source_graph_revision_id: String.t(),
          source_graph_title: String.t(),
          plans: [EvaluationPlanSummary.t()],
          experiments: [EvaluationExperimentSummary.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :run_id,
      :status,
      :failure_reason,
      :manifest_id,
      :manifest_title,
      :graph_id,
      :source_graph_revision_id,
      :source_graph_title
    ])
    |> cast_embed(:plans)
    |> cast_embed(:experiments)
    |> validate_required([
      :run_id,
      :status,
      :manifest_id,
      :manifest_title,
      :graph_id,
      :source_graph_revision_id,
      :source_graph_title
    ])
    |> validate_inclusion(:status, ["running", "completed", "failed"])
    |> Contracts.validate_uuid(:run_id)
    |> Contracts.validate_uuid(:graph_id)
    |> Contracts.validate_uuid(:source_graph_revision_id)
  end
end
