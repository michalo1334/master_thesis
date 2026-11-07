defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.ComparisonIdentity do
  @moduledoc false
  use NetworkDefenseWeb.StudyContract, enums: [:tier]

  embedded_schema do
    field :tier, :string
    field :budget, :integer
    field :alternative, :string
    field :reference, :string
    field :outcome, :string
  end

  @type t :: %__MODULE__{
          tier: String.t(),
          budget: non_neg_integer(),
          alternative: String.t(),
          reference: String.t(),
          outcome: String.t()
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
