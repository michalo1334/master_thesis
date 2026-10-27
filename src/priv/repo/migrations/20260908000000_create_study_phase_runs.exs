defmodule NetworkDefense.Repo.Migrations.CreateStudyPhaseRuns do
  use Ecto.Migration

  def up do
    create table(:evaluation_study_phase_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :study_phase_id,
          references(:evaluation_study_phases, type: :binary_id, on_delete: :delete_all),
          null: false

      add :tier, :string, null: false
      add :tier_position, :integer, null: false
      add :gust_run_id, :integer
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:evaluation_study_phase_runs, [:study_phase_id, :tier_position])
    create unique_index(:evaluation_study_phase_runs, [:study_phase_id, :tier])

    create unique_index(:evaluation_study_phase_runs, [:gust_run_id],
             where: "gust_run_id IS NOT NULL"
           )

    create constraint(:evaluation_study_phase_runs, :study_phase_runs_tier_position_check,
             check: "tier_position >= 0"
           )

    create constraint(
             :evaluation_study_collection_items,
             :study_collection_items_replica_position_check,
             check: "replica_position BETWEEN -1 AND 4"
           )
  end

  def down do
    drop constraint(
           :evaluation_study_collection_items,
           :study_collection_items_replica_position_check
         )

    drop table(:evaluation_study_phase_runs)
  end
end
