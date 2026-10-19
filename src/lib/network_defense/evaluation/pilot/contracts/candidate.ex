defmodule NetworkDefense.Evaluation.Pilot.Contracts.Candidate do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  # One declared candidate size.

  @type t :: %__MODULE__{plan_count: pos_integer(), attacks_per_plan: pos_integer()}

  embedded_schema do
    field :plan_count, :integer
    field :attacks_per_plan, :integer
  end

  def changeset(candidate, attrs), do: cast(candidate, attrs, [:plan_count, :attacks_per_plan])
end
