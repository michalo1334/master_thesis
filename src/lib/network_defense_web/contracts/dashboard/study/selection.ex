defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Selection do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :candidate_id, :string
    field :plan_count_per_side, :integer
    field :attacks_per_plan, :integer
  end

  @type t :: %__MODULE__{
          candidate_id: String.t(),
          plan_count_per_side: non_neg_integer(),
          attacks_per_plan: non_neg_integer()
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
