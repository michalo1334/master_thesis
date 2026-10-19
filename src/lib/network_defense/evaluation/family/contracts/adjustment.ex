defmodule NetworkDefense.Evaluation.Family.Contracts.Adjustment do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  @type t :: %__MODULE__{adjusted_p_value: float(), reject_null: boolean()}

  embedded_schema do
    field :adjusted_p_value, :float
    field :reject_null, :boolean
  end

  def changeset(adjustment, attrs),
    do: cast(adjustment, attrs, [:adjusted_p_value, :reject_null])
end
