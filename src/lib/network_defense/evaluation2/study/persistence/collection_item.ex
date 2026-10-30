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

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "Replica position. Warm-up uses -1 and measured replicas use 0..4."
  @type replica_position :: -1..4

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_phase_run_id: Ecto.UUID.t(),
          replica_position: replica_position(),
          item_position: non_neg_integer(),
          optimization_run_id: Ecto.UUID.t() | nil,
          experiment_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "evaluation2_collection_items" do
    field :study_phase_run_id, :binary_id
    field :replica_position, :integer
    field :item_position, :integer
    field :optimization_run_id, :binary_id
    field :experiment_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end
end
