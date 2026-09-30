defmodule NetworkDefense.Evaluation.StudySpecification do
  @moduledoc """
  One immutable saved study-specification version.

  A version is identified by `study_id` and `specification_version`. Once
  stored it never changes: identical saves are idempotent and different saves
  under the same identity and version are rejected. The title is immutable
  metadata, so a changed title for an existing identity and version is also an
  immutable conflict.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          study_id: String.t() | nil,
          specification_version: pos_integer() | nil,
          title: String.t() | nil,
          content: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "study_specifications" do
    field :study_id, :string
    field :specification_version, :integer
    field :title, :string
    field :content, :map

    timestamps(type: :utc_datetime)
  end

  def changeset(specification, attrs) do
    specification
    |> cast(attrs, [:study_id, :specification_version, :title, :content])
    |> validate_required([:study_id, :specification_version, :title, :content])
    |> validate_length(:study_id, min: 1, max: 255)
    |> validate_length(:title, min: 1, max: 255)
    |> validate_number(:specification_version, greater_than: 0)
    |> unique_constraint([:study_id, :specification_version])
    |> check_constraint(:study_id,
      name: :study_specifications_study_id_present,
      message: "must not be blank"
    )
    |> check_constraint(:title,
      name: :study_specifications_title_present,
      message: "must not be blank"
    )
    |> check_constraint(:specification_version,
      name: :study_specifications_version_positive,
      message: "must be positive"
    )
  end
end
