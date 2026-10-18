defmodule NetworkDefense.Evaluation.Comparison.Contracts.Evidence do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonSide

  embedded_schema do
    field :outcome, :string
    field :attack_seeds, {:array, :integer}
    embeds_one :alternative, ComparisonSide, on_replace: :update
    embeds_one :reference, ComparisonSide, on_replace: :update
  end

  def changeset(evidence, attrs) do
    evidence
    |> cast(attrs, [:outcome, :attack_seeds])
    |> cast_embed(:alternative, required: true)
    |> cast_embed(:reference, required: true)
  end
end
