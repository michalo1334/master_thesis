defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.TierRoot do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  # One evaluation root for one declared tier in one phase.
  #
  # The root seeds the evidence simulation of its tier. The simulator derives
  # every attack column from this root and the ordered trial index through the
  # existing child-seed policy, so the definition declares one root and never a
  # separate column list.
  #
  # A root value may repeat across tiers of one phase, because no contract
  # forbids it. The Pilot and Final root sets stay disjoint, so Final evidence
  # never replays a Pilot observation.

  @type t :: %__MODULE__{tier: String.t(), value: non_neg_integer()}

  embedded_schema do
    field :tier, :string
    field :value, :integer
  end

  def changeset(root, attrs) do
    root
    |> cast(attrs, [:tier, :value])
    |> validate_required([:tier, :value])
    |> validate_number(:value, greater_than_or_equal_to: 0)
  end
end
