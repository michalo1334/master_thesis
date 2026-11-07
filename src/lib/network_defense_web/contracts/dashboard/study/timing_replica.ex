defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.TimingReplica do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :position, :integer
    field :plan_selection_us, :integer
    field :simulation_us, :integer
    field :total_us, :integer
  end

  @type t :: %__MODULE__{
          position: non_neg_integer(),
          plan_selection_us: non_neg_integer(),
          simulation_us: non_neg_integer(),
          total_us: non_neg_integer()
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
