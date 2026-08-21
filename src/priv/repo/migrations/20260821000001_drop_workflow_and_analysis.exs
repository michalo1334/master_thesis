defmodule NetworkDefense.Repo.Migrations.DropWorkflowAndAnalysis do
  use Ecto.Migration

  def change do
    # Document catalog previously referenced these; now safe to drop.
    # Drop analysis linking for artifacts
    alter table(:experiments) do
      remove :analysis_id, :binary_id
    end

    alter table(:optimization_runs) do
      remove :analysis_id, :binary_id
    end

    drop_if_exists table(:analysis_graph_revisions)
    drop_if_exists table(:workflow_steps)
    drop_if_exists table(:workflow_runs)
  end
end
