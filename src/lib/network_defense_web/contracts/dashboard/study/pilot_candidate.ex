defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.PilotCandidate do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :id, :string
    field :plan_count_per_side, :integer
    field :attacks_per_plan, :integer
    field :predicted_runtime_ms, :float

    embeds_many :comparisons, NetworkDefenseWeb.Contracts.Dashboard.Study.PilotComparison,
      on_replace: :delete

    field :worst_guarded_half_width, :float
    field :passes, :boolean
  end

  @type t :: %__MODULE__{
          id: String.t(),
          plan_count_per_side: non_neg_integer(),
          attacks_per_plan: non_neg_integer(),
          predicted_runtime_ms: float(),
          comparisons: [NetworkDefenseWeb.Contracts.Dashboard.Study.PilotComparison.t()],
          worst_guarded_half_width: float() | nil,
          passes: boolean()
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
