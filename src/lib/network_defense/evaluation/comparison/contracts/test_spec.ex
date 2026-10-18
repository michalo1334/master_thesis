defmodule NetworkDefense.Evaluation.Comparison.Contracts.TestSpec do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  embedded_schema do
    field :alternative, :string
  end

  def changeset(spec, attrs), do: cast(spec, attrs, [:alternative])
end
