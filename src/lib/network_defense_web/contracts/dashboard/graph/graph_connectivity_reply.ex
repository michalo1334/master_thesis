defmodule NetworkDefenseWeb.Web.Contracts.GraphConnectivityReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    embeds_many :rules, NetworkDefenseWeb.Web.Contracts.GraphConnectivityRule, on_replace: :delete
  end

  @type t :: %__MODULE__{
          rules: [NetworkDefenseWeb.Web.Contracts.GraphConnectivityRule.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:rules, required: true)
  end
end
