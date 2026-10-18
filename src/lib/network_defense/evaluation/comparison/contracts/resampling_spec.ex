defmodule NetworkDefense.Evaluation.Comparison.Contracts.ResamplingSpec do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  embedded_schema do
    field :seed, :integer
    field :replicates, :integer
  end

  def changeset(spec, attrs), do: cast(spec, attrs, [:seed, :replicates])
end
