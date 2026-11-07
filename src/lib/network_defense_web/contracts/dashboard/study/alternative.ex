defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Alternative do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :strategy, :string
    field :objective, :string
    field :monte_carlo_trials, :integer
  end

  @type t :: %__MODULE__{
          strategy: String.t(),
          objective: String.t() | nil,
          monte_carlo_trials: non_neg_integer() | nil
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
