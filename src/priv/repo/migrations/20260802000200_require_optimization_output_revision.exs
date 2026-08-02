defmodule NetworkDefense.Repo.Migrations.RequireOptimizationOutputRevision do
  use Ecto.Migration

  def change do
    create constraint(:optimization_runs, :optimization_runs_completed_output_revision,
             check: "status != 'completed' OR output_graph_revision_id IS NOT NULL"
           )
  end
end
