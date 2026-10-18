defmodule NetworkDefense.Evaluation.Comparison.Contracts.ComparisonSide do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Comparison.Contracts.PlanEvidence

  embedded_schema do
    field :strategy, :string
    embeds_many :plans, PlanEvidence, on_replace: :delete
  end

  def changeset(side, attrs) do
    side
    |> cast(attrs, [:strategy])
    |> cast_embed(:plans, required: true)
  end
end
