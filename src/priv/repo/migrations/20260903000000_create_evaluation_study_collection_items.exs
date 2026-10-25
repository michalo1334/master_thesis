defmodule NetworkDefense.Repo.Migrations.CreateEvaluationStudyCollectionItems do
  use Ecto.Migration

  def change do
    create table(:evaluation_study_collection_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :study_phase_id,
          references(:evaluation_study_phases, type: :binary_id, on_delete: :delete_all),
          null: false

      add :replica_position, :integer, null: false
      add :item_position, :integer, null: false

      # A collected item links the one optimization run and the one experiment
      # that its task created. Deleting a linked domain record clears the link
      # and keeps the positional identity.
      add :optimization_run_id,
          references(:optimization_runs, type: :binary_id, on_delete: :nilify_all)

      add :experiment_id, references(:experiments, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :evaluation_study_collection_items,
             [:study_phase_id, :replica_position, :item_position],
             name: :evaluation_study_collection_items_position_index
           )
  end
end
