defmodule NetworkDefense.Evaluation.Pilot.Contracts.Selection do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  # Declared selection rule. Version 1 supports one rule.

  @type t :: %__MODULE__{rule: String.t()}

  embedded_schema do
    field :rule, :string
  end

  def changeset(selection, attrs), do: cast(selection, attrs, [:rule])
end
