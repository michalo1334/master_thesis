defmodule NetworkDefenseWeb.Web.Contracts.EvaluationAnalysisRuntimeSummary do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :median_plan_selection_runtime_ms, :float
    field :median_simulation_runtime_ms, :float
    field :evaluator_runtime_ms, :float
  end

  @type t :: %__MODULE__{
          median_plan_selection_runtime_ms: float(),
          median_simulation_runtime_ms: float(),
          evaluator_runtime_ms: float()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :median_plan_selection_runtime_ms,
      :median_simulation_runtime_ms,
      :evaluator_runtime_ms
    ])
    |> validate_required([
      :median_plan_selection_runtime_ms,
      :median_simulation_runtime_ms,
      :evaluator_runtime_ms
    ])
    |> validate_number(:median_plan_selection_runtime_ms, greater_than_or_equal_to: 0)
    |> validate_number(:median_simulation_runtime_ms, greater_than_or_equal_to: 0)
    |> validate_number(:evaluator_runtime_ms, greater_than_or_equal_to: 0)
  end
end
