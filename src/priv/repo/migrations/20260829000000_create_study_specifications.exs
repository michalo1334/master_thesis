defmodule NetworkDefense.Repo.Migrations.CreateStudySpecifications do
  use Ecto.Migration

  def change do
    create table(:study_specifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :study_id, :string, null: false
      add :specification_version, :integer, null: false
      add :title, :string, null: false
      add :content, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:study_specifications, [:study_id, :specification_version])

    create constraint(:study_specifications, :study_specifications_study_id_present,
             check: "study_id ~ '[^[:space:]]'"
           )

    create constraint(:study_specifications, :study_specifications_title_present,
             check: "title ~ '[^[:space:]]'"
           )

    create constraint(:study_specifications, :study_specifications_version_positive,
             check: "specification_version > 0"
           )
  end
end
