defmodule NetworkDefense.Repo.Migrations.AddSuccessfulEdgeIdsToIterationSteps do
  use Ecto.Migration

  def change do
    alter table(:iteration_steps) do
      add :successful_edge_ids, {:array, :uuid}
    end
  end
end
