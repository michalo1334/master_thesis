defmodule NetworkDefenseWeb.Web.Contracts.SaveGraphPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    embeds_one :graph, NetworkDefense.Graph.Contracts.SaveGraphContract, on_replace: :update
  end

  @type t :: %__MODULE__{
          graph: NetworkDefense.Graph.Contracts.SaveGraphContract.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:graph, required: true)
  end
end
