defmodule NetworkDefense.Evaluation2.Study.ProgressSnapshot do
  @moduledoc "Read-only progress of the current accepted phase and replica."
  use Spectral

  alias NetworkDefense.Evaluation2.Study.Status

  @type counter :: %{
          completed: non_neg_integer(),
          total: non_neg_integer() | nil,
          unit: String.t()
        }
  @type t :: %__MODULE__{
          execution_id: String.t(),
          status: Status.t(),
          phase: String.t() | nil,
          tier: String.t() | nil,
          replica: integer() | nil,
          warm_up: boolean(),
          counters: [counter()],
          activity: String.t() | nil
        }
  defstruct [
    :execution_id,
    :status,
    :phase,
    :tier,
    :replica,
    :activity,
    warm_up: false,
    counters: []
  ]
end
