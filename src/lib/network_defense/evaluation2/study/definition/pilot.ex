defmodule NetworkDefense.Evaluation2.Study.Definition.Pilot do
  @moduledoc false

  use Spectral

  alias NetworkDefense.Evaluation2.Study.Definition.{Candidate, Precision, SampleSize}

  # Declared Pilot settings.
  #
  # Candidates declare sample-size pairs only. The collected dimensions derive
  # from the largest candidate plus the extra pool, so no absolute capacity is
  # declared here.

  @type t :: %__MODULE__{
          candidates: [Candidate.t()],
          extra_pool: SampleSize.t(),
          precision: Precision.t()
        }
  defstruct [:candidates, :extra_pool, :precision]
end
