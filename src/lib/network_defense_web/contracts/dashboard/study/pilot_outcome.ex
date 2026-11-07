defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.PilotOutcome do
  @moduledoc false
  use NetworkDefenseWeb.StudyContract, enums: [:outcome]

  embedded_schema do
    field :outcome, :string
    field :candidate_id, :string
    field :plan_count_per_side, :integer
    field :attacks_per_plan, :integer
  end

  @type t :: %__MODULE__{
          outcome: String.t(),
          candidate_id: String.t() | nil,
          plan_count_per_side: non_neg_integer() | nil,
          attacks_per_plan: non_neg_integer() | nil
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
