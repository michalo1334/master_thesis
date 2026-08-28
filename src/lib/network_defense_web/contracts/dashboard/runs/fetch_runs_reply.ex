defmodule NetworkDefenseWeb.Contracts.Dashboard.Runs.FetchRunsReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :runs

  alias NetworkDefenseWeb.Contracts.Dashboard.Runs.RunSummary

  embedded_schema do
    embeds_many :runs, RunSummary, on_replace: :delete
  end

  @type t :: %__MODULE__{
          runs: [RunSummary.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:runs)
  end
end
