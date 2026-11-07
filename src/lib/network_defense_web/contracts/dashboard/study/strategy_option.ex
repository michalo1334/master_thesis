defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.StrategyOption do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :value, :string
    field :scoring_required, :boolean
    field :action_types, {:array, :string}
  end

  @type t :: %__MODULE__{
          value: String.t(),
          scoring_required: boolean(),
          action_types: [String.t()]
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
