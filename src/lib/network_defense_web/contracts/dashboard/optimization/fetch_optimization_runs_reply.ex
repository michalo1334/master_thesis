defmodule NetworkDefenseWeb.Contracts.Dashboard.Optimization.FetchOptimizationRunsReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.OptimizationRunSummary

  embedded_schema do
    embeds_many :runs, OptimizationRunSummary, on_replace: :delete
  end

  @type t :: %__MODULE__{
          runs: [OptimizationRunSummary.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:runs)
  end
end
