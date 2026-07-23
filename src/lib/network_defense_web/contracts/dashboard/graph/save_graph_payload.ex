defmodule NetworkDefenseWeb.Web.Contracts.SaveGraphPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :dashboard

  embedded_schema do
    embeds_one :graph, NetworkDefense.Graph.Contracts.GraphContract, on_replace: :update
  end

  @type t :: %__MODULE__{
          graph: NetworkDefense.Graph.Contracts.GraphContract.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:graph, required: true)
  end
end
