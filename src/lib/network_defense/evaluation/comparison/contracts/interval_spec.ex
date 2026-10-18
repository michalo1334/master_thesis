defmodule NetworkDefense.Evaluation.Comparison.Contracts.IntervalSpec do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  embedded_schema do
    field :confidence_level, :float
  end

  def changeset(spec, attrs), do: cast(spec, attrs, [:confidence_level])
end
