defmodule NetworkDefense.Repo.Migrations.CreateEvaluation2StudyTables do
  use Ecto.Migration

  # Physical Evaluation2 study storage.
  #
  # The legacy `evaluation_*` tables stay untouched: the legacy subsystem still
  # owns them until the final cutover. `gust_run_id` is a plain bigint because the
  # main repository migrates before Gust on a fresh database, so the Gust table
  # may not exist yet. The application-level link owns that pair.

  def change do
    create table(:evaluation2_study_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :study_id, :string, null: false
      add :revision, :integer, null: false
      add :definition, :map, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(
             :evaluation2_study_revisions,
             [:study_id, :revision]
           )

    create constraint(
             :evaluation2_study_revisions,
             :evaluation2_revision_is_positive,
             check: "revision > 0"
           )

    create table(:evaluation2_study_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :study_revision_id,
          references(
            :evaluation2_study_revisions,
            type: :binary_id,
            on_delete: :restrict
          ),
          null: false

      add :state, :string, null: false
      add :pilot_outcome, :map
      add :selection, :map
      add :error, :map

      timestamps(type: :utc_datetime_usec)
    end

    create index(
             :evaluation2_study_executions,
             [:study_revision_id]
           )

    create constraint(
             :evaluation2_study_executions,
             :evaluation2_execution_state,
             check: """
             state IN (
               'collecting_pilot',
               'analyzing_pilot',
               'awaiting_final',
               'collecting_final',
               'analyzing_final',
               'succeeded',
               'failed',
               'cancelled'
             )
             """
           )

    create constraint(
             :evaluation2_study_executions,
             :evaluation2_selection_requires_outcome,
             check: "selection IS NULL OR pilot_outcome IS NOT NULL"
           )

    create constraint(
             :evaluation2_study_executions,
             :evaluation2_awaiting_requires_outcome,
             check: "state <> 'awaiting_final' OR pilot_outcome IS NOT NULL"
           )

    create constraint(
             :evaluation2_study_executions,
             :evaluation2_final_requires_selection,
             check: """
             state NOT IN (
               'collecting_final',
               'analyzing_final',
               'succeeded'
             )
             OR (
               pilot_outcome IS NOT NULL
               AND selection IS NOT NULL
             )
             """
           )

    create constraint(
             :evaluation2_study_executions,
             :evaluation2_failed_requires_error,
             check: "state <> 'failed' OR error IS NOT NULL"
           )

    create table(:evaluation2_study_phases, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :study_execution_id,
          references(
            :evaluation2_study_executions,
            type: :binary_id,
            on_delete: :delete_all
          ),
          null: false

      add :phase, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(
             :evaluation2_study_phases,
             [:study_execution_id, :phase]
           )

    create constraint(
             :evaluation2_study_phases,
             :evaluation2_phase_kind,
             check: """
             phase IN (
               'pilot_collection',
               'pilot_analysis',
               'final_collection',
               'final_analysis'
             )
             """
           )

    create table(:evaluation2_study_phase_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :study_phase_id,
          references(
            :evaluation2_study_phases,
            type: :binary_id,
            on_delete: :delete_all
          ),
          null: false

      add :run_key, :string, null: false
      add :gust_run_id, :bigint, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(
             :evaluation2_study_phase_runs,
             [:study_phase_id, :run_key]
           )

    create unique_index(
             :evaluation2_study_phase_runs,
             [:gust_run_id]
           )

    create constraint(
             :evaluation2_study_phase_runs,
             :evaluation2_run_key,
             check: "run_key IN ('single', 'small', 'medium', 'large')"
           )

    create table(:evaluation2_collection_plans, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :study_phase_run_id,
          references(
            :evaluation2_study_phase_runs,
            type: :binary_id,
            on_delete: :delete_all
          ),
          null: false

      add :items, :map, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(
             :evaluation2_collection_plans,
             [:study_phase_run_id]
           )

    create table(:evaluation2_collection_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :study_phase_run_id,
          references(
            :evaluation2_study_phase_runs,
            type: :binary_id,
            on_delete: :delete_all
          ),
          null: false

      add :replica_position, :integer, null: false
      add :item_position, :integer, null: false

      add :optimization_run_id,
          references(
            :optimization_runs,
            type: :binary_id,
            on_delete: :restrict
          )

      add :experiment_id,
          references(
            :experiments,
            type: :binary_id,
            on_delete: :restrict
          )

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :evaluation2_collection_items,
             [:study_phase_run_id, :replica_position, :item_position],
             name: :evaluation2_collection_item_position
           )

    create unique_index(
             :evaluation2_collection_items,
             [:optimization_run_id],
             where: "optimization_run_id IS NOT NULL"
           )

    create unique_index(
             :evaluation2_collection_items,
             [:experiment_id],
             where: "experiment_id IS NOT NULL"
           )

    create constraint(
             :evaluation2_collection_items,
             :evaluation2_replica_position,
             check: "replica_position BETWEEN -1 AND 4"
           )

    create constraint(
             :evaluation2_collection_items,
             :evaluation2_item_position,
             check: "item_position >= 0"
           )

    create table(:evaluation2_evidence_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :study_phase_id,
          references(
            :evaluation2_study_phases,
            type: :binary_id,
            on_delete: :delete_all
          ),
          null: false

      add :evidence, :map, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(
             :evaluation2_evidence_snapshots,
             [:study_phase_id]
           )

    create table(:evaluation2_study_results, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :study_execution_id,
          references(
            :evaluation2_study_executions,
            type: :binary_id,
            on_delete: :delete_all
          ),
          null: false

      add :family, :map, null: false
      add :timing, :map, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(
             :evaluation2_study_results,
             [:study_execution_id]
           )
  end
end
