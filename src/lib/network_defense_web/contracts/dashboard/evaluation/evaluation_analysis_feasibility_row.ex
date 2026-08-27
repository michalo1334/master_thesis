defmodule NetworkDefenseWeb.Web.Contracts.EvaluationAnalysisFeasibilityRow do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :experiment_id, :string
    field :plan_id, :string
    field :pre_attack_feasible, :boolean
    field :unavailable_required_flow_count, :integer
    field :affected_capability_count, :integer
  end

  @type t :: %__MODULE__{
          experiment_id: String.t(),
          plan_id: String.t(),
          pre_attack_feasible: boolean(),
          unavailable_required_flow_count: non_neg_integer(),
          affected_capability_count: non_neg_integer()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :experiment_id,
      :plan_id,
      :pre_attack_feasible,
      :unavailable_required_flow_count,
      :affected_capability_count
    ])
    |> validate_required([
      :experiment_id,
      :pre_attack_feasible,
      :unavailable_required_flow_count,
      :affected_capability_count
    ])
    |> validate_number(:unavailable_required_flow_count, greater_than_or_equal_to: 0)
    |> validate_number(:affected_capability_count, greater_than_or_equal_to: 0)
  end
end
