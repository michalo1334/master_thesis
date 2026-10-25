defmodule NetworkDefense.Evaluation.Pilot.Contracts.Recommendation do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  @type t :: %__MODULE__{
          candidate_id: String.t(),
          plan_count: pos_integer(),
          attacks_per_plan: pos_integer()
        }

  embedded_schema do
    field :candidate_id, :string
    field :plan_count, :integer
    field :attacks_per_plan, :integer
  end

  def changeset(recommendation, attrs) do
    cast(recommendation, attrs, [:candidate_id, :plan_count, :attacks_per_plan])
  end
end
