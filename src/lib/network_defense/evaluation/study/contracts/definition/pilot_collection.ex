defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.PilotCollection do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Study.Contracts.Definition.TierRoot

  # The declared Pilot collection and its seed roles.
  #
  # The plan count and the attack count are the collection capacity per side.
  # Each plan row of a side consumes one ordered selection seed as the optimizer
  # seed input, so the pool holds at least one seed per row. The roots seed the
  # evidence simulation, one root per declared tier.
  #
  # Order is preserved and no prefix or subset policy exists. An unused seed is
  # allowed, so a later capacity decision never forces a new format.

  @type t :: %__MODULE__{
          plan_count_per_side: pos_integer(),
          attacks_per_plan: pos_integer(),
          selection_seeds: [non_neg_integer()],
          roots: [TierRoot.t()]
        }

  embedded_schema do
    field :plan_count_per_side, :integer
    field :attacks_per_plan, :integer
    field :selection_seeds, {:array, :integer}
    embeds_many :roots, TierRoot, on_replace: :delete
  end

  def changeset(collection, attrs) do
    collection
    |> change()
    |> cast(attrs, [:plan_count_per_side, :attacks_per_plan, :selection_seeds])
    |> cast_embed(:roots, required: true)
    |> validate_required([:plan_count_per_side, :attacks_per_plan, :selection_seeds])
    |> validate_number(:plan_count_per_side, greater_than_or_equal_to: 5)
    |> validate_number(:attacks_per_plan, greater_than_or_equal_to: 10)
    |> validate_length(:selection_seeds, min: 1)
  end
end
