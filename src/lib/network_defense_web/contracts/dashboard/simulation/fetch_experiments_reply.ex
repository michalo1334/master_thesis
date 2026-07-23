defmodule NetworkDefenseWeb.Web.Contracts.FetchExperimentsReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    embeds_many :experiments, NetworkDefenseWeb.Web.Contracts.ExperimentSummary,
      on_replace: :delete
  end

  @type t :: %__MODULE__{
          experiments: [NetworkDefenseWeb.Web.Contracts.ExperimentSummary.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:experiments)
  end
end
