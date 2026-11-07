defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Candidate do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :id, :string
    field :plans, :integer
    field :attacks, :integer
  end

  @type t :: %__MODULE__{
          id: String.t(),
          plans: non_neg_integer(),
          attacks: non_neg_integer()
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
