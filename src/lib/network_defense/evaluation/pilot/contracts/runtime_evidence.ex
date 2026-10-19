defmodule NetworkDefense.Evaluation.Pilot.Contracts.RuntimeEvidence do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  # Bounded runtime evidence declared at snapshot creation. It lets the
  # selector predict candidate runtime without measuring inside a mapped task.

  @type t :: %__MODULE__{
          plan_selection_ms: [float()],
          attack_trial_ms: [float()],
          tier_count: pos_integer(),
          strategy_group_count: pos_integer()
        }

  embedded_schema do
    field :plan_selection_ms, {:array, :float}
    field :attack_trial_ms, {:array, :float}
    field :tier_count, :integer
    field :strategy_group_count, :integer
  end

  def changeset(evidence, attrs) do
    cast(evidence, attrs, [
      :plan_selection_ms,
      :attack_trial_ms,
      :tier_count,
      :strategy_group_count
    ])
  end
end
