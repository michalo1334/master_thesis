defmodule NetworkDefense.Evaluation2.Study.Persistence.CollectionItem do
  @moduledoc false

  # One replica-and-item coordinate of a collection phase run.
  #
  # The item belongs to the specific `StudyPhaseRun` that planned and executes
  # it. The item owns its replica and item positions, while the phase-run plan
  # owns the work request.
  #
  # The two effect links make a Gust retry reuse the same optimization run and
  # the same simulation experiment.

  @typedoc "Replica position. Warm-up uses -1 and measured replicas use 0..4."
  @type replica_position :: -1..4

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_phase_run_id: Ecto.UUID.t(),
          replica_position: replica_position(),
          item_position: non_neg_integer(),
          optimization_run_id: Ecto.UUID.t() | nil,
          experiment_id: Ecto.UUID.t() | nil
        }

  defstruct [
    :id,
    :study_phase_run_id,
    :replica_position,
    :item_position,
    :optimization_run_id,
    :experiment_id
  ]
end
