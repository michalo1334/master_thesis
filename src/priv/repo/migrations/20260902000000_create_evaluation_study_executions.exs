defmodule NetworkDefense.Repo.Migrations.CreateEvaluationStudyExecutions do
  use Ecto.Migration

  def change do
    create table(:evaluation_study_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :study_revision_id,
          references(:evaluation_study_revisions, type: :binary_id, on_delete: :restrict),
          null: false

      add :state, :string, null: false
      add :error, :map

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:evaluation_study_executions, :evaluation_study_executions_state_valid,
             check:
               "state IN ('collecting_pilot', 'analyzing_pilot', 'awaiting_final', 'collecting_final', 'analyzing_final', 'succeeded', 'failed', 'cancelled')"
           )

    create table(:evaluation_study_phases, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :execution_id,
          references(:evaluation_study_executions, type: :binary_id, on_delete: :restrict),
          null: false

      add :phase, :string, null: false
      # The Gust run lives in the Gust migration set of the same database, so
      # the phase stores the run ID without a cross-set foreign key.
      add :gust_run_id, :bigint

      add :snapshot_id,
          references(:evaluation_evidence_snapshots, type: :binary_id, on_delete: :restrict)

      add :result_ref, :map
      add :error, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:evaluation_study_phases, [:execution_id, :phase],
             name: :evaluation_study_phases_execution_id_phase_index
           )

    create constraint(:evaluation_study_phases, :evaluation_study_phases_phase_valid,
             check:
               "phase IN ('pilot_collection', 'pilot_analysis', 'final_collection', 'final_analysis')"
           )
  end
end
