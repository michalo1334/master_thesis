defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Counter do
  @moduledoc false
  use NetworkDefenseWeb.StudyContract, enums: [unit: :counter_unit]

  embedded_schema do
    field :completed, :integer
    field :total, :integer
    field :unit, :string
  end

  @type t :: %__MODULE__{
          completed: non_neg_integer(),
          total: non_neg_integer() | nil,
          unit: String.t()
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
