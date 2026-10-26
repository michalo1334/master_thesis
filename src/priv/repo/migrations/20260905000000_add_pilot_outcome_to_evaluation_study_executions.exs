defmodule NetworkDefense.Repo.Migrations.AddPilotOutcomeToEvaluationStudyExecutions do
  use Ecto.Migration

  def change do
    alter table(:evaluation_study_executions) do
      add :pilot_outcome, :map
    end
  end
end
