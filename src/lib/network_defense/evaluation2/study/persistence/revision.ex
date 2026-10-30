defmodule NetworkDefense.Evaluation2.Study.Persistence.Revision do
  @moduledoc false

  # Frozen study definition.
  #
  # One revision holds the parsed and normalized definition that creation already
  # accepted. The revision stores its declared identity for the supported reads,
  # and it keeps an internal identifier for its foreign keys.
  #
  # A later setting change creates a new revision instead of editing this one.
  # `Study.Persistence` replaces the JSONB `definition` map with the typed
  # `Study.Definition` value before the record leaves the boundary.

  use Ecto.Schema

  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Revision, as: RevisionIdentity

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_id: String.t(),
          revision: RevisionIdentity.revision(),
          definition: Definition.t(),
          inserted_at: DateTime.t()
        }

  schema "evaluation2_study_revisions" do
    field :study_id, :string
    field :revision, :integer
    field :definition, :map

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
