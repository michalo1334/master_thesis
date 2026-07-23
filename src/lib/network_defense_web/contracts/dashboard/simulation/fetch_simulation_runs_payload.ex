defmodule NetworkDefenseWeb.Web.Contracts.FetchSimulationRunsPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :dashboard

  embedded_schema do
    field :graph_ids, {:array, :string}, default: []
  end

  @type t :: %__MODULE__{
          graph_ids: [String.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:graph_ids])
  end
end
