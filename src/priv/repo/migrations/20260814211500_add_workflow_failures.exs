defmodule NetworkDefense.Repo.Migrations.AddWorkflowFailures do
  use Ecto.Migration

  def change do
    alter table(:workflow_runs) do
      add :error, :text
    end

    alter table(:workflow_steps) do
      add :error, :text
    end
  end
end
