defmodule NetworkDefense.Evaluation.Family.Contracts.ResultComparison do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonStatistics
  alias NetworkDefense.Evaluation.Family.Contracts.{Adjustment, Identity}

  @type t :: %__MODULE__{
          identity: Identity.t(),
          statistics: ComparisonStatistics.t(),
          adjustment: Adjustment.t()
        }

  embedded_schema do
    embeds_one :identity, Identity, on_replace: :update
    embeds_one :statistics, ComparisonStatistics, on_replace: :update
    embeds_one :adjustment, Adjustment, on_replace: :update
  end

  def changeset(comparison, attrs) do
    comparison
    |> cast(attrs, [])
    |> cast_embed(:identity, required: true)
    |> cast_embed(:statistics, required: true)
    |> cast_embed(:adjustment, required: true)
  end
end
