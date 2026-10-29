defmodule NetworkDefense.Evaluation2.CollectionItem do
  @moduledoc """
  Immutable planned work of one collection item.

  Planning writes the item once. The item fixes its planned replica position, its
  position inside the phase, and the stored `WorkItem` that later tasks execute.
  The optimization run and experiment links make a Gust retry reuse the same
  domain effects instead of creating new ones.

  The stored work value is the planner contract of the declared definition, so it
  keeps the declared definition terminology. Evaluation2 records that name
  observed data use the `NetworkDefense.Evaluation2.Tier` type instead.
  """

  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.WorkItem

  @typedoc "Replica position of the planned work. Warm-up uses -1, measured replicas use 0..4."
  @type replica_position :: -1..4

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          phase_id: Ecto.UUID.t(),
          replica_position: replica_position(),
          item_position: non_neg_integer(),
          work: WorkItem.t(),
          optimization_run_id: Ecto.UUID.t() | nil,
          experiment_id: Ecto.UUID.t() | nil
        }

  defstruct [
    :id,
    :phase_id,
    :replica_position,
    :item_position,
    :work,
    :optimization_run_id,
    :experiment_id
  ]
end
