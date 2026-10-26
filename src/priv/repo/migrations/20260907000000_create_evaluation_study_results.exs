defmodule NetworkDefense.Repo.Migrations.CreateEvaluationStudyResults do
  use Ecto.Migration

  def change do
    create table(:evaluation_study_results, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :execution_id,
          references(:evaluation_study_executions, type: :binary_id, on_delete: :restrict),
          null: false

      add :schema_version, :integer, null: false
      add :data, :map, null: false

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create unique_index(:evaluation_study_results, [:execution_id])

    create constraint(:evaluation_study_results, :evaluation_study_results_schema_version_valid,
             check: "schema_version = 1"
           )

    execute(
      """
      CREATE FUNCTION prevent_evaluation_study_result_change()
      RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'evaluation study results are immutable';
      END;
      $$ LANGUAGE plpgsql
      """,
      "DROP FUNCTION prevent_evaluation_study_result_change()"
    )

    execute(
      """
      CREATE TRIGGER evaluation_study_results_immutable
      BEFORE UPDATE OR DELETE ON evaluation_study_results
      FOR EACH ROW EXECUTE FUNCTION prevent_evaluation_study_result_change()
      """,
      "DROP TRIGGER evaluation_study_results_immutable ON evaluation_study_results"
    )
  end
end
