defmodule NetworkDefense.Evaluation.StudyCollectionItem do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  # One stable collection item for one position in one study phase.
  #
  # The immutable definition and the deterministic work order define the
  # position, so the database enforces one row for each phase, replica
  # position, and item position. The row holds no scientific identity: the
  # candidate, the seeds, the comparison, the side, and the graph stay in the
  # declared work of that position.
  #
  # A collected item links the one optimization run and the one experiment that
  # its task created. Both links start empty and the reservation step fills
  # them, so a repeated request reuses the linked records instead of creating
  # new domain effects.
  #
  # The repository validates that both positions are non-negative integers
  # before it inserts one row, so the table holds no range check of its own.

  @fields [
    :study_phase_id,
    :replica_position,
    :item_position,
    :optimization_run_id,
    :experiment_id
  ]

  @link_fields [:optimization_run_id, :experiment_id]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "evaluation_study_collection_items" do
    field :study_phase_id, :binary_id
    field :replica_position, :integer
    field :item_position, :integer
    field :optimization_run_id, :binary_id
    field :experiment_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: binary(),
          study_phase_id: binary(),
          replica_position: non_neg_integer(),
          item_position: non_neg_integer(),
          optimization_run_id: binary() | nil,
          experiment_id: binary() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  def create_changeset(item, attrs) do
    item
    |> cast(attrs, @fields)
    |> validate_required([:study_phase_id, :replica_position, :item_position])
    |> unique_constraint([:study_phase_id, :replica_position, :item_position],
      name: :evaluation_study_collection_items_position_index
    )
    |> foreign_key_constraint(:study_phase_id)
    |> foreign_key_constraint(:optimization_run_id)
    |> foreign_key_constraint(:experiment_id)
  end

  @doc """
  Links one reserved runtime record.

  A reservation writes one link at a time, so the positional identity and the
  other link stay unchanged.
  """
  def link_changeset(item, attrs) do
    item
    |> cast(attrs, @link_fields)
    |> foreign_key_constraint(:optimization_run_id)
    |> foreign_key_constraint(:experiment_id)
  end
end
