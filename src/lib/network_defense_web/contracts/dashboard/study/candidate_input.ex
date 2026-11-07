defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.CandidateInput do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :id, :string
    field :plans, :integer
    field :attacks, :integer
  end

  @type t :: %__MODULE__{
          id: String.t(),
          plans: integer() | String.t(),
          attacks: integer() | String.t()
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
