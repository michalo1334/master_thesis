defmodule NetworkDefense.Evaluation.Pilot.Contracts.Precision do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  # Declared Precision Pilot settings. No default exists.

  @type t :: %__MODULE__{
          target_half_width: float(),
          guard_quantile: float(),
          confidence_level: float(),
          bootstrap_replicates: pos_integer()
        }

  embedded_schema do
    field :target_half_width, :float
    field :guard_quantile, :float
    field :confidence_level, :float
    field :bootstrap_replicates, :integer
  end

  def changeset(precision, attrs) do
    cast(precision, attrs, [
      :target_half_width,
      :guard_quantile,
      :confidence_level,
      :bootstrap_replicates
    ])
  end
end
