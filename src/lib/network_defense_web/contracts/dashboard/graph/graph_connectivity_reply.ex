defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphConnectivityReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    embeds_many :rules, NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphConnectivityRule,
      on_replace: :delete
  end

  @type t :: %__MODULE__{
          rules: [NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphConnectivityRule.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:rules, required: true)
  end
end
