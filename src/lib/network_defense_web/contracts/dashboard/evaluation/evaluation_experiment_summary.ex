defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationExperimentSummary do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :id, :string
    field :optimization_run_id, :string
    field :graph_id, :string
    field :graph_revision_id, :string
    field :graph_title, :string
    field :trial_count, :integer
    field :expected_blast_radius, :float
    field :median_blast_radius, :integer
    field :blast_radius_p95, :integer
    field :blast_radius_p99, :integer
    field :min_blast_radius, :integer
    field :max_blast_radius, :integer
  end

  @type t :: %__MODULE__{
          id: String.t(),
          optimization_run_id: String.t() | nil,
          graph_id: String.t() | nil,
          graph_revision_id: String.t() | nil,
          graph_title: String.t() | nil,
          trial_count: integer(),
          expected_blast_radius: float(),
          median_blast_radius: integer(),
          blast_radius_p95: integer(),
          blast_radius_p99: integer(),
          min_blast_radius: integer(),
          max_blast_radius: integer()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :id,
      :optimization_run_id,
      :graph_id,
      :graph_revision_id,
      :graph_title,
      :trial_count,
      :expected_blast_radius,
      :median_blast_radius,
      :blast_radius_p95,
      :blast_radius_p99,
      :min_blast_radius,
      :max_blast_radius
    ])
    |> validate_required([:id, :trial_count])
    |> NetworkDefense.Contracts.validate_uuid(:id)
    |> NetworkDefense.Contracts.validate_uuid(:optimization_run_id)
    |> NetworkDefense.Contracts.validate_uuid(:graph_id)
    |> NetworkDefense.Contracts.validate_uuid(:graph_revision_id)
  end
end
