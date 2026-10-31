defmodule NetworkDefense.Evaluation2.Study.Definition.Precision do
  @moduledoc false

  use Spectral

  # Declared Pilot precision target. The interval level is shared through the
  # study inference settings, so no confidence copy lives here.
  # target_half_width uses the frozen model's outcome units, like the interval.

  @type t :: %__MODULE__{
          outer_subsamples: pos_integer(),
          target_half_width: float(),
          guard_quantile: float()
        }
  defstruct [:outer_subsamples, :target_half_width, :guard_quantile]
end
