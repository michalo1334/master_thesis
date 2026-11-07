defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.TierInput do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :tier, :string
    field :graph_revision_id, :string
    field :foothold_node_id, :string
    field :budgets, {:array, :integer}

    embeds_many :alternatives, NetworkDefenseWeb.Contracts.Dashboard.Study.AlternativeInput,
      on_replace: :delete
  end

  @type t :: %__MODULE__{
          tier: String.t(),
          graph_revision_id: String.t(),
          foothold_node_id: String.t(),
          budgets: [integer() | String.t()],
          alternatives: [NetworkDefenseWeb.Contracts.Dashboard.Study.AlternativeInput.t()]
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
