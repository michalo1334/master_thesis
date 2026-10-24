defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.Candidate do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  # One candidate of the Pilot grid.
  #
  # The identifier and the count pair must both be unique, because one measured
  # precision result belongs to exactly one candidate. The minimum counts are
  # the smallest sizes the comparison contract accepts.

  @type t :: %__MODULE__{
          id: String.t(),
          plan_count_per_side: pos_integer(),
          attacks_per_plan: pos_integer()
        }

  @min_plan_count 5
  @min_attacks 10

  embedded_schema do
    field :id, :string
    field :plan_count_per_side, :integer
    field :attacks_per_plan, :integer
  end

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [:id, :plan_count_per_side, :attacks_per_plan])
    |> validate_required([:id, :plan_count_per_side, :attacks_per_plan])
    |> validate_number(:plan_count_per_side, greater_than_or_equal_to: @min_plan_count)
    |> validate_number(:attacks_per_plan, greater_than_or_equal_to: @min_attacks)
  end
end
