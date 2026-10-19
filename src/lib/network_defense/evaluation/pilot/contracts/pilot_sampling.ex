defmodule NetworkDefense.Evaluation.Pilot.Contracts.PilotSampling do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  # Outer sampling declaration. The base seed is declared here; the historical
  # comparison seed is derived from the declared comparison order.

  @type t :: %__MODULE__{outer_subsamples: pos_integer(), seed: non_neg_integer()}

  embedded_schema do
    field :outer_subsamples, :integer
    field :seed, :integer
  end

  def changeset(sampling, attrs), do: cast(sampling, attrs, [:outer_subsamples, :seed])
end
