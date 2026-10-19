defmodule NetworkDefense.Evaluation.Pilot.Contracts.CandidateGrid do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  # Declared candidate values. Scientific minimums come from the accepted
  # evidence contract: at least five plans per side and at least ten attacks.

  @type t :: %__MODULE__{
          plan_count_candidates: [pos_integer()],
          attacks_per_plan_candidates: [pos_integer()]
        }

  embedded_schema do
    field :plan_count_candidates, {:array, :integer}
    field :attacks_per_plan_candidates, {:array, :integer}
  end

  def changeset(grid, attrs) do
    cast(grid, attrs, [:plan_count_candidates, :attacks_per_plan_candidates])
  end
end
