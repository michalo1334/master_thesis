defmodule NetworkDefense.Evaluation.Comparison.Contracts.PlanEvidence do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  embedded_schema do
    field :id, :string
    field :mission_impacts, {:array, :float}
  end

  def changeset(plan, attrs) do
    cast(plan, attrs, [:id, :mission_impacts])
  end
end
