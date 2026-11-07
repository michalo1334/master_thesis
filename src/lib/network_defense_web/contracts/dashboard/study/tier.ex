defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Tier do
  @moduledoc false
  use NetworkDefenseWeb.StudyContract, enums: [:tier]

  embedded_schema do
    field :tier, :string
    field :graph_revision_id, :string
    field :foothold_node_id, :string
    field :budgets, {:array, :integer}

    embeds_many :alternatives, NetworkDefenseWeb.Contracts.Dashboard.Study.Alternative,
      on_replace: :delete
  end

  @type t :: %__MODULE__{
          tier: String.t(),
          graph_revision_id: String.t(),
          foothold_node_id: String.t(),
          budgets: [non_neg_integer()],
          alternatives: [NetworkDefenseWeb.Contracts.Dashboard.Study.Alternative.t()]
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
