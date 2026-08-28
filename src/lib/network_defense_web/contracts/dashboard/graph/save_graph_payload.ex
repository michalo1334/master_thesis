defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.SaveGraphPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  alias NetworkDefense.Graph.Contracts.SaveGraphContract

  embedded_schema do
    embeds_one :graph, SaveGraphContract, on_replace: :update
  end

  @type t :: %__MODULE__{
          graph: SaveGraphContract.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:graph, required: true)
  end
end
