defmodule NetworkDefense.Repo.Migrations.AddInputDigestToEvaluationRuns do
  use Ecto.Migration

  def change do
    alter table(:evaluation_runs) do
      add :input_digest, :string
    end
  end
end
