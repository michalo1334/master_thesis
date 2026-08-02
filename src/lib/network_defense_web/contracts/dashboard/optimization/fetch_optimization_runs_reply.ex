defmodule NetworkDefenseWeb.Web.Contracts.FetchOptimizationRunsReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  embedded_schema do
    embeds_many :runs, NetworkDefenseWeb.Web.Contracts.OptimizationRunSummary, on_replace: :delete
  end

  @type t :: %__MODULE__{
          runs: [NetworkDefenseWeb.Web.Contracts.OptimizationRunSummary.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:runs)
  end
end
