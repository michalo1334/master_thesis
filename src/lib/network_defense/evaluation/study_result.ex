defmodule NetworkDefense.Evaluation.StudyResult do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @fields [:execution_id, :schema_version, :data]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "evaluation_study_results" do
    field :execution_id, :binary_id
    field :schema_version, :integer
    field :data, :map

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          execution_id: Ecto.UUID.t(),
          schema_version: 1,
          data: map(),
          inserted_at: DateTime.t()
        }

  def create_changeset(result, attrs) do
    result
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_inclusion(:schema_version, [1])
    |> unique_constraint(:execution_id)
    |> foreign_key_constraint(:execution_id)
    |> check_constraint(:schema_version,
      name: :evaluation_study_results_schema_version_valid,
      message: "must equal 1"
    )
  end
end
