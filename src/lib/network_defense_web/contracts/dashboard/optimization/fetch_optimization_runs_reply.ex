defmodule NetworkDefenseWeb.Contracts.Dashboard.Optimization.FetchOptimizationRunsReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  embedded_schema do
    embeds_many :runs, NetworkDefenseWeb.Contracts.Dashboard.Optimization.OptimizationRunSummary,
      on_replace: :delete
  end

  @type t :: %__MODULE__{
          runs: [NetworkDefenseWeb.Contracts.Dashboard.Optimization.OptimizationRunSummary.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:runs)
  end
end
