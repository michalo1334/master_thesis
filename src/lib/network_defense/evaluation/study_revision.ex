defmodule NetworkDefense.Evaluation.StudyRevision do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  # Immutable normalized study revision.
  #
  # One row holds the declared identity and the normalized definition. The
  # application parses and resolves the definition before it inserts one row,
  # and it stores no source YAML. Only creation exists, so a stored revision
  # cannot change.

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "evaluation_study_revisions" do
    field :study_id, :string
    field :revision, :integer
    field :schema_version, :integer
    field :definition, :map

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: binary(),
          study_id: String.t(),
          revision: pos_integer(),
          schema_version: integer(),
          definition: map(),
          inserted_at: DateTime.t()
        }

  def create_changeset(revision, attrs) do
    revision
    |> cast(attrs, [:study_id, :revision, :schema_version, :definition])
    |> validate_required([:study_id, :revision, :schema_version, :definition])
    |> validate_number(:revision, greater_than: 0)
    |> unique_constraint([:study_id, :revision],
      name: :evaluation_study_revisions_study_id_revision_index
    )
  end
end
