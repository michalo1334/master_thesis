defmodule NetworkDefenseWeb.Web.Contracts.SaveGraphPayload do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  embedded_schema do
    embeds_one :graph, NetworkDefenseWeb.Web.Contracts.GraphContract, on_replace: :update
  end

  @type t :: %__MODULE__{
          graph: NetworkDefenseWeb.Web.Contracts.GraphContract.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:graph, required: true)
  end
end
