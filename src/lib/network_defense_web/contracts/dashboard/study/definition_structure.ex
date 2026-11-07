defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.DefinitionStructure do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :comparisons, :integer
    field :collection_groups, :integer
    field :pilot_plans, :integer
    field :pilot_attacks, :integer
  end

  @type t :: %__MODULE__{
          comparisons: non_neg_integer(),
          collection_groups: non_neg_integer(),
          pilot_plans: pos_integer(),
          pilot_attacks: pos_integer()
        }
  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
