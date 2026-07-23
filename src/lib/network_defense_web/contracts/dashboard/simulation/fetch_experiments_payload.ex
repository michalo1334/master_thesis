defmodule NetworkDefenseWeb.Web.Contracts.FetchExperimentsPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

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
