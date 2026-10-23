defmodule NetworkDefenseWeb.Contracts.Dashboard.Optimization.FetchOptimizationRunsPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  embedded_schema do
    field :graph_revision_ids, {:array, :string}, default: []
  end

  @type t :: %__MODULE__{
          graph_revision_ids: [String.t()]
        }

  def changeset(schema, attrs), do: Contracts.graph_revision_ids_changeset(schema, attrs)
end
