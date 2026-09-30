defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyTierRunSummary do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :id, :string
    field :manifest_id, :string
    field :manifest_title, :string
    field :graph_title, :string
    field :completed_at, :string
    field :plan_count, :integer, default: 0
    field :trial_count, :integer, default: 0
  end

  @type t :: %__MODULE__{
          id: String.t(),
          manifest_id: String.t() | nil,
          manifest_title: String.t() | nil,
          graph_title: String.t() | nil,
          completed_at: String.t() | nil,
          plan_count: non_neg_integer(),
          trial_count: non_neg_integer()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :id,
      :manifest_id,
      :manifest_title,
      :graph_title,
      :completed_at,
      :plan_count,
      :trial_count
    ])
    |> validate_required([:id])
    |> Contracts.validate_uuid(:id)
    |> validate_number(:plan_count, greater_than_or_equal_to: 0)
    |> validate_number(:trial_count, greater_than_or_equal_to: 0)
  end
end
