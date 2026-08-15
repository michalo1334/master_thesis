defmodule NetworkDefense.Repo.Migrations.AddWorkflowCorrelationId do
  use Ecto.Migration

  def change do
    alter table(:workflow_runs) do
      add :correlation_id, :string
    end

    create unique_index(:workflow_runs, [:template, :correlation_id])
  end
end
