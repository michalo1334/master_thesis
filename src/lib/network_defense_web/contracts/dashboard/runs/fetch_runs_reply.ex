defmodule NetworkDefenseWeb.Web.Contracts.FetchRunsReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :runs

  embedded_schema do
    embeds_many :runs, NetworkDefenseWeb.Web.Contracts.RunSummary, on_replace: :delete
  end

  @type t :: %__MODULE__{
          runs: [NetworkDefenseWeb.Web.Contracts.RunSummary.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:runs)
  end
end
